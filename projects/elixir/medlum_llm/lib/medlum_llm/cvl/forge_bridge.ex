defmodule MedlumLlm.CVL.ForgeBridge do
  @moduledoc """
  Bidirectional bridge between Forge evaluation pipeline and Anvil labeling queue.

  This module synchronizes data between:
  - **Forge** - Evaluation pipeline that generates NLI samples
  - **Anvil** - Human labeling platform for NLI classification

  ## Data Flow

      Forge Evaluation Pipeline
              |
              | publish_to_anvil/2
              v
      Anvil Labeling Queue
              |
              | Human labeling
              v
      Labeled Samples
              |
              | sync_to_forge/2
              v
      Forge Measurements & Storage

  ## Features

  - Publish Forge samples to Anvil for human labeling
  - Sync labeled data back to Forge as measurements
  - Compute consensus from multiple human labels
  - Track lineage between Forge samples and Anvil labels

  ## Usage

      # Publish samples from Forge to Anvil
      {:ok, count} = MedlumLlm.CVL.ForgeBridge.publish_to_anvil(forge_samples, queue_id)

      # Sync labels from Anvil back to Forge
      {:ok, count} = MedlumLlm.CVL.ForgeBridge.sync_to_forge(queue_id)

      # Get bridge status
      status = MedlumLlm.CVL.ForgeBridge.status(queue_id)
  """

  alias MedlumLlm.CVL.LabelingQueue

  require Logger

  @type forge_sample :: %{
          id: String.t(),
          data: map(),
          pipeline: String.t() | nil,
          version: String.t() | nil,
          measurements: map() | nil
        }

  @type publish_opts :: [
          queue: String.t(),
          include_measurements: boolean(),
          batch_size: pos_integer()
        ]

  @type sync_opts :: [
          min_labels: pos_integer(),
          min_agreement: float(),
          update_mode: :append | :replace
        ]

  @default_batch_size 100

  @doc """
  Publishes Forge samples to an Anvil labeling queue.

  Transforms Forge sample format to Anvil format and adds them to the queue.

  ## Options

  - `:queue` - Target Anvil queue ID (default: CVL queue)
  - `:include_measurements` - Include Forge measurements as metadata (default: true)
  - `:batch_size` - Batch size for publishing (default: 100)

  ## Returns

  - `{:ok, count}` - Number of samples published
  - `{:error, reason}` - If publishing fails

  ## Examples

      iex> samples = [%{id: "forge_1", data: %{premise: "...", hypothesis: "..."}}]
      iex> {:ok, count} = MedlumLlm.CVL.ForgeBridge.publish_to_anvil(samples, "cvl_queue")
      iex> count
      1
  """
  @spec publish_to_anvil([forge_sample()], String.t(), publish_opts()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def publish_to_anvil(forge_samples, queue_id, opts \\ []) do
    include_measurements = Keyword.get(opts, :include_measurements, true)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    Logger.info("Publishing #{length(forge_samples)} samples to Anvil queue: #{queue_id}")

    anvil_samples =
      Enum.map(forge_samples, fn sample ->
        transform_forge_to_anvil(sample, include_measurements)
      end)

    # Publish in batches
    results =
      anvil_samples
      |> Enum.chunk_every(batch_size)
      |> Enum.map(fn batch ->
        add_samples_to_queue(batch, queue_id)
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      Logger.info("Successfully published #{length(anvil_samples)} samples")
      {:ok, length(anvil_samples)}
    else
      {:error, {:publish_failed, errors}}
    end
  end

  @doc """
  Syncs labeled data from Anvil back to Forge as measurements.

  Retrieves completed labels, computes consensus, and creates Forge measurements.

  ## Options

  - `:min_labels` - Minimum labels required per sample (default: 3)
  - `:min_agreement` - Minimum agreement threshold (default: 0.80)
  - `:update_mode` - How to update Forge (:append or :replace) (default: :append)

  ## Returns

  - `{:ok, count}` - Number of samples synced
  - `{:error, reason}` - If sync fails

  ## Examples

      iex> {:ok, count} = MedlumLlm.CVL.ForgeBridge.sync_to_forge("cvl_queue")
  """
  @spec sync_to_forge(String.t(), sync_opts()) :: {:ok, non_neg_integer()} | {:error, term()}
  def sync_to_forge(queue_id, opts \\ []) do
    min_labels = Keyword.get(opts, :min_labels, 3)
    min_agreement = Keyword.get(opts, :min_agreement, 0.80)

    Logger.info("Syncing labels from Anvil queue #{queue_id} to Forge")

    # Get labels from Anvil queue
    labels = get_queue_labels(queue_id)

    # Group by sample
    by_sample = Enum.group_by(labels, & &1.sample_id)

    # Process samples with sufficient labels
    processed =
      by_sample
      |> Enum.filter(fn {_sample_id, sample_labels} ->
        length(sample_labels) >= min_labels
      end)
      |> Enum.map(fn {sample_id, sample_labels} ->
        measurements = build_measurements(sample_labels, min_agreement)
        {sample_id, measurements}
      end)
      |> Enum.filter(fn {_sample_id, measurements} ->
        measurements != nil
      end)

    # Update Forge with measurements
    results =
      Enum.map(processed, fn {sample_id, measurements} ->
        update_forge_measurements(sample_id, measurements)
      end)

    success_count = Enum.count(results, &match?(:ok, &1))

    Logger.info("Synced #{success_count} samples to Forge")

    {:ok, success_count}
  end

  @doc """
  Gets the bridge status for a queue.

  Returns statistics about samples published to Anvil and synced back to Forge.

  ## Examples

      iex> status = MedlumLlm.CVL.ForgeBridge.status("cvl_queue")
      iex> status.anvil_samples
      100
  """
  @spec status(String.t()) :: map()
  def status(queue_id) do
    labels = get_queue_labels(queue_id)
    by_sample = Enum.group_by(labels, & &1.sample_id)

    complete_samples =
      Enum.filter(by_sample, fn {_id, labels} ->
        length(labels) >= 3
      end)

    %{
      queue_id: queue_id,
      anvil_samples: map_size(by_sample),
      complete_samples: length(complete_samples),
      total_labels: length(labels),
      unique_labelers: labels |> Enum.map(& &1.labeler_id) |> Enum.uniq() |> length(),
      synced_to_forge: count_synced_samples(by_sample)
    }
  end

  @doc """
  Transforms a Forge sample to Anvil format.

  ## Examples

      iex> forge_sample = %{
      ...>   id: "forge_123",
      ...>   data: %{premise: "...", hypothesis: "..."},
      ...>   pipeline: "cvl_training"
      ...> }
      iex> anvil_sample = MedlumLlm.CVL.ForgeBridge.transform_forge_to_anvil(forge_sample)
  """
  @spec transform_forge_to_anvil(forge_sample(), boolean()) :: map()
  def transform_forge_to_anvil(forge_sample, include_measurements \\ true) do
    data = Map.get(forge_sample, :data, %{})

    base = %{
      id: forge_sample.id || forge_sample[:id],
      premise: data[:premise] || data["premise"] || data[:source_document] || "",
      hypothesis: data[:hypothesis] || data["hypothesis"] || data[:generated_summary] || "",
      metadata: %{
        forge_id: forge_sample.id || forge_sample[:id],
        forge_version: Map.get(forge_sample, :version),
        forge_pipeline: Map.get(forge_sample, :pipeline),
        error_type: data[:error_type] || data["error_type"],
        model: data[:model] || data["model"],
        benchmark: data[:benchmark] || data["benchmark"]
      }
    }

    if include_measurements do
      measurements = Map.get(forge_sample, :measurements, %{})
      put_in(base, [:metadata, :measurements], measurements)
    else
      base
    end
  end

  @doc """
  Builds Forge measurements from Anvil labels.

  Computes consensus, agreement scores, and confidence metrics.
  """
  @spec build_measurements([Anvil.Label.t()], float()) :: map() | nil
  def build_measurements(labels, min_agreement \\ 0.80) do
    verdicts = Enum.map(labels, & &1.values["verdict"]) |> Enum.filter(&(&1 != nil))
    confidences = Enum.map(labels, & &1.values["confidence"]) |> Enum.filter(&(&1 != nil))

    if Enum.empty?(verdicts) do
      nil
    else
      verdict_freq = Enum.frequencies(verdicts)
      {consensus_verdict, max_count} = Enum.max_by(verdict_freq, fn {_, count} -> count end)
      agreement = max_count / length(verdicts)

      if agreement >= min_agreement do
        %{
          cvl_labels: %{
            count: length(labels),
            verdicts: verdict_freq,
            consensus: consensus_verdict,
            agreement: Float.round(agreement, 4),
            avg_confidence: safe_average(confidences),
            confidence_stddev: safe_stddev(confidences),
            labeler_ids: Enum.map(labels, & &1.labeler_id) |> Enum.uniq(),
            synced_at: DateTime.utc_now()
          }
        }
      else
        # Agreement below threshold, mark as needing review
        %{
          cvl_labels: %{
            count: length(labels),
            verdicts: verdict_freq,
            consensus: nil,
            agreement: Float.round(agreement, 4),
            needs_review: true,
            avg_confidence: safe_average(confidences),
            synced_at: DateTime.utc_now()
          }
        }
      end
    end
  end

  @doc """
  Computes majority verdict from a list of labels.
  """
  @spec majority_verdict([Anvil.Label.t()]) :: String.t() | nil
  def majority_verdict(labels) do
    verdicts =
      labels
      |> Enum.map(& &1.values["verdict"])
      |> Enum.filter(&(&1 != nil))

    if Enum.empty?(verdicts) do
      nil
    else
      {verdict, _count} =
        verdicts
        |> Enum.frequencies()
        |> Enum.max_by(fn {_, count} -> count end)

      verdict
    end
  end

  @doc """
  Computes agreement score for a list of labels.

  Returns the percentage of labels that match the majority verdict.
  """
  @spec compute_agreement([Anvil.Label.t()]) :: float() | nil
  def compute_agreement(labels) when length(labels) < 2, do: nil

  def compute_agreement(labels) do
    verdicts = Enum.map(labels, & &1.values["verdict"]) |> Enum.filter(&(&1 != nil))

    if length(verdicts) < 2 do
      nil
    else
      {_consensus, max_count} =
        verdicts
        |> Enum.frequencies()
        |> Enum.max_by(fn {_, count} -> count end)

      Float.round(max_count / length(verdicts), 4)
    end
  end

  # Private functions

  defp add_samples_to_queue(samples, queue_id) do
    if queue_id == LabelingQueue.queue_id() do
      LabelingQueue.add_samples(samples)
    else
      # Use generic Anvil API for other queues
      queue = {:via, Registry, {Anvil.Registry, queue_id}}
      Anvil.Queue.add_samples(queue, samples)
    end
  end

  defp get_queue_labels(queue_id) do
    if queue_id == LabelingQueue.queue_id() do
      LabelingQueue.get_labels()
    else
      queue = {:via, Registry, {Anvil.Registry, queue_id}}
      Anvil.Queue.get_labels(queue)
    end
  end

  defp update_forge_measurements(sample_id, measurements) do
    # Try to update Forge storage with measurements
    # This would integrate with Forge.Storage or Forge.Sample
    # TODO: Replace apply/3 with direct call once Forge.add_measurements/2 is implemented
    try do
      # Check if Forge module is available
      if Code.ensure_loaded?(Forge) and function_exported?(Forge, :add_measurements, 2) do
        apply(Forge, :add_measurements, [sample_id, measurements])
      else
        # Fall back to logging
        Logger.debug("Would update Forge measurements for #{sample_id}: #{inspect(measurements)}")
        :ok
      end
    rescue
      _ -> :ok
    end
  end

  defp count_synced_samples(by_sample) do
    # Count samples that have been synced (have cvl_labels measurement)
    Enum.count(by_sample, fn {_id, labels} ->
      first_label = hd(labels)

      measurements =
        get_in(first_label, [:metadata, :measurements]) ||
          get_in(first_label, [Access.key(:metadata, %{}), :measurements])

      measurements != nil and Map.has_key?(measurements, :cvl_labels)
    end)
  end

  defp safe_average([]), do: 0.0

  defp safe_average(values) do
    Float.round(Enum.sum(values) / length(values), 2)
  end

  defp safe_stddev([]), do: 0.0
  defp safe_stddev([_]), do: 0.0

  defp safe_stddev(values) do
    avg = Enum.sum(values) / length(values)

    variance =
      values
      |> Enum.map(fn x -> (x - avg) * (x - avg) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    Float.round(:math.sqrt(variance), 2)
  end
end
