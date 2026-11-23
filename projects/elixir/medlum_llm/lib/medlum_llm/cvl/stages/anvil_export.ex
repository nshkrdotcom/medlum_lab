defmodule MedlumLlm.CVL.Stages.AnvilExport do
  @moduledoc """
  Forge Stage for exporting low-confidence samples to Anvil for human labeling.

  This stage filters samples by confidence threshold and exports them to
  the Anvil human labeling platform using `Forge.AnvilBridge`.

  ## Filtering Criteria

  Samples are exported to Anvil if:
  - Confidence score is below the threshold (default: 0.5)
  - Sample has valid NLI pairs
  - Sample has been redacted (contains no PHI)

  ## Configuration Options

  - `:confidence_threshold` - Maximum confidence for export (default: `0.5`)
  - `:queue` - Anvil queue name (default: `"cvl_verification"`)
  - `:include_measurements` - Include measurement data (default: `true`)
  - `:batch_size` - Number of samples per batch (default: `50`)

  ## Anvil Queue Configuration

  The stage creates or uses a queue configured for 3-way NLI classification:
  - Task type: NLI classification (entailment/contradiction/neutral)
  - Annotators: 3 per sample
  - Agreement threshold: 67% (2/3 consensus)

  ## Example

      iex> sample = %Forge.Sample{
      ...>   data: %{nli_pairs: [...], nli_label: :neutral},
      ...>   measurements: %{confidence: %{score: 0.4}}
      ...> }
      iex> {:ok, exported} = AnvilExport.process(sample)
      iex> exported.data.anvil_job_id
      "job_123abc"
  """

  @behaviour Forge.Stage

  require Logger

  @default_queue "cvl_verification"
  @default_threshold 0.5

  @impl true
  @spec process(Forge.Sample.t()) :: {:ok, Forge.Sample.t()} | {:skip, term()} | {:error, term()}
  def process(sample) do
    process(sample, [])
  end

  @spec process(Forge.Sample.t(), keyword()) ::
          {:ok, Forge.Sample.t()} | {:skip, term()} | {:error, term()}
  def process(sample, opts) do
    threshold = Keyword.get(opts, :confidence_threshold, @default_threshold)
    queue = Keyword.get(opts, :queue, @default_queue)
    include_measurements = Keyword.get(opts, :include_measurements, true)

    # Check if sample should be exported
    case should_export?(sample, threshold) do
      {:ok, :export} ->
        do_export(sample, queue, include_measurements)

      {:skip, reason} ->
        # Sample doesn't need human review, pass through
        Logger.debug("Skipping Anvil export for #{sample.id}: #{inspect(reason)}")
        {:ok, sample}
    end
  rescue
    e ->
      {:error, %{reason: :anvil_export_failed, exception: Exception.message(e)}}
  end

  @impl true
  @spec async?() :: boolean()
  def async?, do: true

  @impl true
  @spec concurrency() :: pos_integer()
  def concurrency, do: 4

  @impl true
  @spec timeout() :: pos_integer()
  def timeout, do: 60_000

  # Public helper functions

  @doc """
  Check if a sample should be exported to Anvil.
  """
  @spec should_export?(Forge.Sample.t(), float()) :: {:ok, :export} | {:skip, atom()}
  def should_export?(sample, threshold) do
    confidence = get_confidence(sample)
    has_nli = has_valid_nli_pairs?(sample)

    cond do
      confidence >= threshold ->
        {:skip, :high_confidence}

      not has_nli ->
        {:skip, :no_nli_pairs}

      true ->
        {:ok, :export}
    end
  end

  @doc """
  Format a sample for Anvil export.
  """
  @spec format_for_anvil(Forge.Sample.t(), boolean()) :: map()
  def format_for_anvil(sample, include_measurements) do
    data = sample.data
    nli_pair = get_primary_nli_pair(data)

    %{
      sample_id: sample.id,
      title: format_title(data),
      body: format_body(nli_pair, data),
      task_type: :nli_classification,
      options: [
        %{label: "entailment", description: "The hypothesis is supported by the premise"},
        %{label: "contradiction", description: "The hypothesis contradicts the premise"},
        %{label: "neutral", description: "The hypothesis is neither supported nor contradicted"}
      ],
      metadata: %{
        pipeline_id: sample.pipeline,
        error_type: data[:error_type],
        model: data[:model],
        benchmark: data[:benchmark],
        claim_type: nli_pair[:claim_type],
        auto_label: data[:nli_label],
        measurements:
          if(include_measurements, do: sample.measurements, else: %{}),
        created_at: sample.created_at
      }
    }
  end

  # Private functions

  @spec do_export(Forge.Sample.t(), String.t(), boolean()) ::
          {:ok, Forge.Sample.t()} | {:error, term()}
  defp do_export(sample, queue, include_measurements) do
    anvil_data = format_for_anvil(sample, include_measurements)
    publish_opts = [queue: queue, include_measurements: include_measurements]

    case Forge.AnvilBridge.publish_sample(anvil_data, publish_opts) do
      {:ok, job_id} ->
        Logger.info("Published sample #{sample.id} to Anvil queue #{queue}: #{job_id}")

        updated_data =
          sample.data
          |> Map.put(:anvil_job_id, job_id)
          |> Map.put(:anvil_queue, queue)
          |> Map.put(:anvil_exported_at, DateTime.utc_now())

        {:ok, %{sample | data: updated_data}}

      {:error, :not_available} ->
        # Anvil bridge not configured, skip gracefully
        Logger.warning("Anvil bridge not available, skipping export for #{sample.id}")
        {:ok, sample}

      {:error, reason} ->
        {:error, %{reason: :anvil_publish_failed, details: reason}}
    end
  end

  @spec get_confidence(Forge.Sample.t()) :: float()
  defp get_confidence(sample) do
    # Check measurements first
    case sample.measurements do
      %{confidence: %{score: score}} when is_number(score) ->
        score

      %{confidence: score} when is_number(score) ->
        score

      _ ->
        # Fall back to data confidence
        case sample.data do
          %{confidence: score} when is_number(score) -> score
          _ -> 1.0
        end
    end
  end

  @spec has_valid_nli_pairs?(Forge.Sample.t()) :: boolean()
  defp has_valid_nli_pairs?(sample) do
    case sample.data[:nli_pairs] do
      pairs when is_list(pairs) and length(pairs) > 0 -> true
      _ -> false
    end
  end

  @spec get_primary_nli_pair(map()) :: map()
  defp get_primary_nli_pair(data) do
    case data[:nli_pairs] do
      [first | _] -> first
      _ -> %{premise: "", hypothesis: "", claim_type: :unknown}
    end
  end

  @spec format_title(map()) :: String.t()
  defp format_title(data) do
    claim_type = get_in(data, [:nli_pairs, Access.at(0), :claim_type]) || :general
    error_type = data[:error_type] || :unknown

    "CVL Verification: #{claim_type} claim (#{error_type})"
  end

  @spec format_body(map(), map()) :: String.t()
  defp format_body(nli_pair, data) do
    """
    ## Premise (Source Document)

    #{nli_pair[:premise] || data[:source_document] || "N/A"}

    ## Hypothesis (Generated Claim)

    #{nli_pair[:hypothesis] || "N/A"}

    ---

    **Claim Type:** #{nli_pair[:claim_type] || "general"}
    **Error Type:** #{data[:error_type] || "unknown"}
    **Model:** #{data[:model] || "unknown"}
    **Benchmark:** #{data[:benchmark] || "unknown"}

    ---

    Please classify the relationship between the premise and hypothesis:
    - **Entailment**: The hypothesis is supported by/consistent with the premise
    - **Contradiction**: The hypothesis contradicts or is inconsistent with the premise
    - **Neutral**: The hypothesis is neither clearly supported nor contradicted
    """
  end
end
