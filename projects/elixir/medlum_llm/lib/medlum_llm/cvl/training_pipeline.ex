defmodule MedlumLlm.CVL.TrainingPipeline do
  @moduledoc """
  Forge Pipeline for generating CVL training data from evaluation failures.

  This pipeline reads evaluation results, extracts NLI pairs, redacts PII,
  runs CVL agent measurements, and exports data for human labeling via Anvil.

  ## Pipeline Stages

  1. **Source** - `EvaluationFailureSource` reads eval failures from JSON
  2. **Normalize** - Clean and normalize text
  3. **Extract Claims** - Split text into verifiable claims
  4. **Generate NLI** - Create premise/hypothesis pairs
  5. **Redact PII** - HIPAA-compliant PHI redaction
  6. **Anvil Export** - Send low-confidence samples for human review

  ## Measurements

  - Individual CVL agents: medication, lab, ontology, temporal, differential
  - `AgentConsensus` - Weighted voting across agents
  - `Confidence` - Calibrated confidence score

  ## Configuration

  The pipeline can be configured via Mix config:

      config :medlum_llm, MedlumLlm.CVL.TrainingPipeline,
        results_dir: "priv/eval_results",
        confidence_threshold: 0.5,
        anvil_queue: "cvl_verification"

  ## Usage

      # Run the pipeline
      MedlumLlm.CVL.TrainingPipeline.run()

      # Run with specific filters
      MedlumLlm.CVL.TrainingPipeline.run(filters: [:incorrect, :contradiction])

      # Stream samples with backpressure
      MedlumLlm.CVL.TrainingPipeline.stream()
      |> Stream.each(&process_sample/1)
      |> Stream.run()
  """

  use Forge.Pipeline

  alias MedlumLlm.CVL.Stages
  alias MedlumLlm.Storage.AuditedPostgres

  # Pipeline definition using Forge DSL
  pipeline :cvl_training do
    source MedlumLlm.CVL.EvaluationFailureSource,
      results_dir: "priv/eval_results",
      filters: [:error, :incorrect, :low_confidence],
      min_confidence: 0.5

    stage Stages.NormalizeText

    stage Stages.ClaimExtraction,
      claim_types: [:medication, :diagnosis, :lab_value, :procedure, :temporal]

    stage Stages.NLIPairGenerator

    stage Stages.PIIRedaction,
      mode: :aggressive

    stage Stages.AnvilExport,
      queue: "cvl_verification",
      confidence_threshold: 0.5

    measurement MedlumLlm.CVL.Measurements.MedicationAgent
    measurement MedlumLlm.CVL.Measurements.LabAgent
    measurement MedlumLlm.CVL.Measurements.OntologyAgent
    measurement MedlumLlm.CVL.Measurements.TemporalAgent
    measurement MedlumLlm.CVL.Measurements.DifferentialAgent

    measurement MedlumLlm.CVL.Measurements.AgentConsensus
    measurement MedlumLlm.CVL.Measurements.Confidence

    storage AuditedPostgres,
      pipeline_name: :cvl_training
  end

  # Public API

  @doc """
  Run the full CVL training pipeline.

  ## Options

  - `:results_dir` - Directory containing eval results (default: "priv/eval_results")
  - `:filters` - Error types to include (default: `[:error, :incorrect, :low_confidence]`)
  - `:min_confidence` - Minimum confidence threshold (default: `0.5`)

  ## Returns

  `{:ok, stats}` where stats includes sample counts and timing information.
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    pipeline_config = __pipeline__(:cvl_training)

    # Override config with provided options
    config =
      pipeline_config
      |> override_source_opts(opts)
      |> override_stage_opts(:anvil_export, opts)

    Forge.Runner.run(config, opts)
  end

  @doc """
  Stream samples through the pipeline with backpressure.

  Returns a lazy stream of processed samples.
  """
  @spec stream(keyword()) :: Enumerable.t()
  def stream(opts \\ []) do
    pipeline_config = __pipeline__(:cvl_training)

    config =
      pipeline_config
      |> override_source_opts(opts)

    # TODO: Replace with direct call once Forge.Runner.Streaming.stream/2 is implemented
    if Code.ensure_loaded?(Forge.Runner.Streaming) and
         function_exported?(Forge.Runner.Streaming, :stream, 2) do
      apply(Forge.Runner.Streaming, :stream, [config, opts])
    else
      raise "Forge.Runner.Streaming.stream/2 is not yet implemented"
    end
  end

  @doc """
  Get the pipeline configuration.
  """
  @spec config() :: Forge.Pipeline.Config.t()
  def config do
    __pipeline__(:cvl_training)
  end

  @doc """
  Get all samples that need human review (low confidence).
  """
  @spec samples_for_review(keyword()) :: {:ok, [Forge.Sample.t()]} | {:error, term()}
  def samples_for_review(opts \\ []) do
    threshold = Keyword.get(opts, :confidence_threshold, 0.5)

    # Query storage for low-confidence samples
    with {:ok, storage_state} <- AuditedPostgres.init(pipeline_name: :cvl_training),
         {:ok, samples, _state} <- AuditedPostgres.list([status: :ready], storage_state) do
      low_confidence_samples =
        samples
        |> Enum.filter(fn sample ->
          confidence = get_in(sample.measurements, [:confidence, :calibrated_score]) || 1.0
          confidence < threshold
        end)

      {:ok, low_confidence_samples}
    end
  end

  @doc """
  Export training data to JSONL format.

  ## Options

  - `:output_path` - Path for output file (required)
  - `:filters` - Sample status filters (default: `[status: :labeled]`)
  - `:include_measurements` - Include measurement data (default: `true`)
  """
  @spec export_training_data(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def export_training_data(opts) do
    output_path = Keyword.fetch!(opts, :output_path)
    filters = Keyword.get(opts, :filters, [status: :labeled])
    include_measurements = Keyword.get(opts, :include_measurements, true)

    with {:ok, storage_state} <- AuditedPostgres.init(pipeline_name: :cvl_training),
         {:ok, samples, _state} <- AuditedPostgres.list(filters, storage_state) do
      lines =
        samples
        |> Enum.map(&format_training_sample(&1, include_measurements))
        |> Enum.map(&Jason.encode!/1)

      File.write!(output_path, Enum.join(lines, "\n"))
      {:ok, length(lines)}
    end
  end

  # Private helpers

  @spec override_source_opts(Forge.Pipeline.Config.t(), keyword()) :: Forge.Pipeline.Config.t()
  defp override_source_opts(config, opts) do
    source_overrides =
      opts
      |> Keyword.take([:results_dir, :filters, :min_confidence])

    if Enum.empty?(source_overrides) do
      config
    else
      new_source_opts = Keyword.merge(config.source_opts, source_overrides)
      %{config | source_opts: new_source_opts}
    end
  end

  @spec override_stage_opts(Forge.Pipeline.Config.t(), atom(), keyword()) ::
          Forge.Pipeline.Config.t()
  defp override_stage_opts(config, stage_name, opts) do
    stage_overrides =
      case stage_name do
        :anvil_export -> Keyword.take(opts, [:confidence_threshold, :queue])
        _ -> []
      end

    if Enum.empty?(stage_overrides) do
      config
    else
      new_stages =
        Enum.map(config.stages, fn {module, stage_opts} = stage ->
          if module == Stages.AnvilExport do
            {module, Keyword.merge(stage_opts, stage_overrides)}
          else
            stage
          end
        end)

      %{config | stages: new_stages}
    end
  end

  @spec format_training_sample(Forge.Sample.t(), boolean()) :: map()
  defp format_training_sample(sample, include_measurements) do
    data = sample.data

    base = %{
      sample_id: sample.id,
      premise: get_in(data, [:nli_pairs, Access.at(0), :premise]) || data[:source_document],
      hypothesis: get_in(data, [:nli_pairs, Access.at(0), :hypothesis]) || "",
      label: data[:nli_label] || :neutral,
      claim_type: get_in(data, [:nli_pairs, Access.at(0), :claim_type]) || :general,
      error_type: data[:error_type],
      model: data[:model],
      benchmark: data[:benchmark]
    }

    if include_measurements do
      Map.put(base, :measurements, %{
        consensus_verdict: get_in(sample.measurements, [:consensus, :verdict]),
        confidence_score: get_in(sample.measurements, [:confidence, :calibrated_score]),
        confidence_level: get_in(sample.measurements, [:confidence, :confidence_level]),
        agreement: get_in(sample.measurements, [:consensus, :agreement])
      })
    else
      base
    end
  end
end
