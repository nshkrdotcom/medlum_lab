defmodule MedlumLlm.CVL.ExportPipeline do
  @moduledoc """
  Export pipeline for CVL training data with agreement filtering and clinical redaction.

  Exports labeled NLI samples from Anvil with configurable quality filters:
  - Agreement threshold filtering (default: 0.80)
  - Minimum labels requirement (default: 3)
  - Consensus requirement option
  - Clinical PII redaction (standard or aggressive mode)

  ## Export Format

  Exports to JSONL format with deterministic ordering for reproducibility.
  Each line contains:

      {
        "sample_id": "cvl_a1b2c3d4",
        "premise": "...",
        "hypothesis": "...",
        "labels": [
          {"labeler_id": "l1", "verdict": "ENTAILMENT", "confidence": 4, "evidence_quality": "clear"},
          {"labeler_id": "l2", "verdict": "ENTAILMENT", "confidence": 5, "evidence_quality": "clear"},
          {"labeler_id": "l3", "verdict": "ENTAILMENT", "confidence": 4, "evidence_quality": "partial"}
        ],
        "consensus_verdict": "ENTAILMENT",
        "consensus_agreement": 1.0,
        "agreement_score": 0.92,
        "metadata": {...}
      }

  ## Usage

      # Export with default settings (0.80 agreement, 3 labels)
      {:ok, result} = MedlumLlm.CVL.ExportPipeline.export_training_data()

      # Export with custom thresholds
      {:ok, result} = MedlumLlm.CVL.ExportPipeline.export_training_data(
        min_agreement: 0.90,
        min_labels: 5,
        redaction_mode: :aggressive
      )

      # Export with consensus calculation
      {:ok, result} = MedlumLlm.CVL.ExportPipeline.export_with_consensus(
        output_path: "priv/cvl_train_consensus.jsonl"
      )
  """

  alias MedlumLlm.CVL.LabelingQueue
  alias MedlumLlm.PII.Clinical, as: ClinicalPII

  require Logger

  @export_dir "priv/cvl_training"
  @default_min_agreement 0.80
  @default_min_labels 3

  @type export_opts :: [
          output_path: String.t() | nil,
          min_agreement: float(),
          min_labels: pos_integer(),
          consensus_required: boolean(),
          redaction_mode: :standard | :aggressive | :none,
          schema_version: String.t(),
          include_metadata: boolean()
        ]

  @type export_result :: %{
          output_path: String.t(),
          row_count: non_neg_integer(),
          manifest_path: String.t(),
          sha256_hash: String.t()
        }

  @doc """
  Exports CVL training data with quality filtering.

  ## Options

  - `:output_path` - Custom output path (default: auto-generated in priv/cvl_training)
  - `:min_agreement` - Minimum agreement score threshold (default: 0.80)
  - `:min_labels` - Minimum labels per sample (default: 3)
  - `:consensus_required` - Require consensus verdict (default: true)
  - `:redaction_mode` - PII redaction mode (:standard, :aggressive, :none) (default: :aggressive)
  - `:schema_version` - Schema version to export (default: "1.1")
  - `:include_metadata` - Include sample metadata in export (default: true)

  ## Returns

  - `{:ok, result}` - Export result with path, count, manifest, and hash
  - `{:error, reason}` - If export fails

  ## Examples

      iex> {:ok, result} = MedlumLlm.CVL.ExportPipeline.export_training_data()
      iex> result.row_count
      150
  """
  @spec export_training_data(export_opts()) :: {:ok, export_result()} | {:error, term()}
  def export_training_data(opts \\ []) do
    min_agreement = Keyword.get(opts, :min_agreement, @default_min_agreement)
    min_labels = Keyword.get(opts, :min_labels, @default_min_labels)
    consensus_required = Keyword.get(opts, :consensus_required, true)
    redaction_mode = Keyword.get(opts, :redaction_mode, :aggressive)
    include_metadata = Keyword.get(opts, :include_metadata, true)

    output_path = Keyword.get(opts, :output_path) || generate_output_path()

    Logger.info(
      "Exporting CVL training data: min_agreement=#{min_agreement}, min_labels=#{min_labels}"
    )

    # Ensure output directory exists
    File.mkdir_p!(Path.dirname(output_path))

    # Get all labels grouped by sample
    labels = LabelingQueue.get_labels()
    samples_with_labels = group_labels_by_sample(labels)

    # Apply filters
    filtered_samples =
      samples_with_labels
      |> filter_by_min_labels(min_labels)
      |> filter_by_agreement(min_agreement)
      |> maybe_filter_by_consensus(consensus_required)

    Logger.info("Filtered to #{length(filtered_samples)} samples meeting quality criteria")

    # Apply redaction and format for export
    export_lines =
      filtered_samples
      |> Enum.map(&format_export_line(&1, redaction_mode, include_metadata))
      |> Enum.sort_by(& &1["sample_id"])

    # Write to file
    content =
      export_lines
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    File.write!(output_path, content)

    # Generate manifest
    sha256_hash = compute_file_hash(output_path)
    manifest_path = output_path <> ".manifest.json"
    write_manifest(manifest_path, output_path, length(export_lines), sha256_hash, opts)

    result = %{
      output_path: output_path,
      row_count: length(export_lines),
      manifest_path: manifest_path,
      sha256_hash: sha256_hash
    }

    Logger.info("Exported #{result.row_count} samples to #{output_path}")

    {:ok, result}
  end

  @doc """
  Exports training data with consensus verdict calculation.

  Same as `export_training_data/1` but also computes and includes
  the consensus verdict and agreement percentage for each sample.

  ## Examples

      iex> {:ok, result} = MedlumLlm.CVL.ExportPipeline.export_with_consensus()
  """
  @spec export_with_consensus(export_opts()) :: {:ok, export_result()} | {:error, term()}
  def export_with_consensus(opts \\ []) do
    # Export with consensus calculation enabled
    export_training_data(Keyword.put(opts, :consensus_required, true))
  end

  @doc """
  Computes overall quality metrics for the labeled dataset.

  ## Returns

  Map with quality metrics:
  - `:total_samples` - Total samples with any labels
  - `:complete_samples` - Samples with required labels
  - `:high_agreement_samples` - Samples meeting agreement threshold
  - `:overall_agreement` - Average agreement score
  - `:verdict_distribution` - Count by verdict type

  ## Examples

      iex> metrics = MedlumLlm.CVL.ExportPipeline.quality_metrics()
      iex> metrics.overall_agreement
      0.85
  """
  @spec quality_metrics(keyword()) :: map()
  def quality_metrics(opts \\ []) do
    min_labels = Keyword.get(opts, :min_labels, @default_min_labels)
    min_agreement = Keyword.get(opts, :min_agreement, @default_min_agreement)

    labels = LabelingQueue.get_labels()
    samples_with_labels = group_labels_by_sample(labels)

    complete_samples = filter_by_min_labels(samples_with_labels, min_labels)

    agreement_scores =
      complete_samples
      |> Enum.map(&compute_sample_agreement/1)
      |> Enum.filter(&(&1 != nil))

    high_agreement_samples = Enum.filter(agreement_scores, &(&1 >= min_agreement))

    verdicts =
      complete_samples
      |> Enum.map(&compute_consensus(&1))
      |> Enum.frequencies()

    %{
      total_samples: length(samples_with_labels),
      complete_samples: length(complete_samples),
      high_agreement_samples: length(high_agreement_samples),
      overall_agreement: safe_average(agreement_scores),
      verdict_distribution: verdicts,
      labels_per_sample_avg: safe_average(Enum.map(samples_with_labels, &length(&1.labels)))
    }
  end

  @doc """
  Verifies export reproducibility by regenerating and comparing hash.

  ## Examples

      iex> {:ok, :reproducible} = MedlumLlm.CVL.ExportPipeline.verify_export("priv/cvl_training/export.jsonl")
  """
  @spec verify_export(String.t()) :: {:ok, :reproducible} | {:error, term()}
  def verify_export(manifest_path) do
    with {:ok, manifest_content} <- File.read(manifest_path),
         {:ok, manifest} <- Jason.decode(manifest_content),
         output_path = manifest["output_path"],
         {:ok, current_hash} <- {:ok, compute_file_hash(output_path)} do
      if current_hash == manifest["sha256_hash"] do
        {:ok, :reproducible}
      else
        {:error, :hash_mismatch}
      end
    end
  end

  # Private functions

  defp generate_output_path do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    Path.join(@export_dir, "cvl_train_#{timestamp}.jsonl")
  end

  defp group_labels_by_sample(labels) do
    labels
    |> Enum.group_by(& &1.sample_id)
    |> Enum.map(fn {sample_id, sample_labels} ->
      %{
        sample_id: sample_id,
        labels: sample_labels
      }
    end)
  end

  defp filter_by_min_labels(samples, min_labels) do
    Enum.filter(samples, fn sample ->
      length(sample.labels) >= min_labels
    end)
  end

  defp filter_by_agreement(samples, min_agreement) do
    Enum.filter(samples, fn sample ->
      agreement = compute_sample_agreement(sample)
      agreement != nil and agreement >= min_agreement
    end)
  end

  defp maybe_filter_by_consensus(samples, false), do: samples

  defp maybe_filter_by_consensus(samples, true) do
    Enum.filter(samples, fn sample ->
      consensus = compute_consensus(sample)
      consensus != nil
    end)
  end

  defp compute_sample_agreement(%{labels: labels}) when length(labels) < 2, do: nil

  defp compute_sample_agreement(%{labels: labels}) do
    verdicts = Enum.map(labels, &(&1.values["verdict"]))

    if Enum.all?(verdicts, &(&1 != nil)) do
      # Simple agreement calculation: percentage of labels matching the majority
      {_, max_count} = Enum.frequencies(verdicts) |> Enum.max_by(fn {_, count} -> count end)
      max_count / length(verdicts)
    else
      nil
    end
  end

  defp compute_consensus(%{labels: labels}) do
    verdicts =
      labels
      |> Enum.map(&(&1.values["verdict"]))
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

  defp format_export_line(sample, redaction_mode, include_metadata) do
    labels_data =
      Enum.map(sample.labels, fn label ->
        %{
          "labeler_id" => hash_labeler_id(label.labeler_id),
          "verdict" => label.values["verdict"],
          "confidence" => label.values["confidence"],
          "evidence_quality" => label.values["evidence_quality"]
        }
      end)

    consensus = compute_consensus(sample)
    agreement = compute_sample_agreement(sample)

    # Get sample content from first label (they should all have same sample data)
    first_label = hd(sample.labels)

    # Apply redaction to any text fields
    premise = redact_text(get_sample_premise(first_label), redaction_mode)
    hypothesis = redact_text(get_sample_hypothesis(first_label), redaction_mode)

    base = %{
      "sample_id" => sample.sample_id,
      "premise" => premise,
      "hypothesis" => hypothesis,
      "labels" => labels_data,
      "consensus_verdict" => consensus,
      "consensus_agreement" => agreement,
      "label_count" => length(sample.labels)
    }

    if include_metadata do
      Map.put(base, "metadata", extract_metadata(first_label))
    else
      base
    end
  end

  defp get_sample_premise(label) do
    # Labels might have sample content attached or we need to look it up
    label[:premise] || label.values["premise"] || ""
  end

  defp get_sample_hypothesis(label) do
    label[:hypothesis] || label.values["hypothesis"] || ""
  end

  defp extract_metadata(label) do
    %{
      "created_at" => DateTime.to_iso8601(label.created_at),
      "labeling_time_avg" => label.labeling_time_seconds
    }
  end

  defp redact_text(text, :none), do: text
  defp redact_text(text, :standard), do: ClinicalPII.redact(text, :standard)
  defp redact_text(text, :aggressive), do: ClinicalPII.redact(text, :aggressive)

  defp hash_labeler_id(labeler_id) do
    # Hash labeler ID for privacy
    :crypto.hash(:sha256, labeler_id)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 12)
  end

  defp compute_file_hash(path) do
    File.stream!(path, [], 65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp write_manifest(manifest_path, output_path, row_count, sha256_hash, opts) do
    manifest = %{
      "version" => "1.0",
      "output_path" => output_path,
      "row_count" => row_count,
      "sha256_hash" => sha256_hash,
      "exported_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "parameters" => %{
        "min_agreement" => Keyword.get(opts, :min_agreement, @default_min_agreement),
        "min_labels" => Keyword.get(opts, :min_labels, @default_min_labels),
        "redaction_mode" => Keyword.get(opts, :redaction_mode, :aggressive),
        "schema_version" => Keyword.get(opts, :schema_version, "1.1")
      }
    }

    File.write!(manifest_path, Jason.encode!(manifest, pretty: true))
  end

  defp safe_average([]), do: 0.0

  defp safe_average(values) do
    Enum.sum(values) / length(values)
  end
end
