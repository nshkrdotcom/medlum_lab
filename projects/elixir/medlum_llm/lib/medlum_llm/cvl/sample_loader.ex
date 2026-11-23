defmodule MedlumLlm.CVL.SampleLoader do
  @moduledoc """
  Loads evaluation failures from Forge and transforms them into Anvil samples.

  This module bridges the Forge evaluation pipeline with Anvil's labeling queue,
  converting evaluation failures (incorrect answers, low confidence, contradictions)
  into NLI pairs for human labeling.

  ## Data Flow

      Forge Evaluation Run
              |
              v
      Evaluation Failures (JSON)
              |
              v
      SampleLoader.load_from_eval_run/2
              |
              v
      Anvil Samples (NLI pairs)
              |
              v
      CVL Labeling Queue

  ## Sample Transformation

  Forge samples are transformed into Anvil samples with:
  - Unique sample ID (cvl_ prefix)
  - Premise (source document from evaluation)
  - Hypothesis (generated summary/claim to verify)
  - Metadata (eval_run_id, model, benchmark, error_type)

  ## Usage

      # Load samples from a specific evaluation run
      {:ok, count} = MedlumLlm.CVL.SampleLoader.load_from_eval_run("eval_20260125_1234")

      # Load with filters
      {:ok, count} = MedlumLlm.CVL.SampleLoader.load_from_eval_run(
        "eval_20260125_1234",
        error_types: [:contradiction, :incorrect],
        max_samples: 100
      )

      # Load from multiple evaluation runs
      {:ok, count} = MedlumLlm.CVL.SampleLoader.load_from_eval_runs([
        "eval_20260125_1234",
        "eval_20260125_5678"
      ])
  """

  alias MedlumLlm.CVL.LabelingQueue

  require Logger

  @type load_opts :: [
          error_types: [atom()],
          max_samples: pos_integer() | nil,
          min_confidence: float(),
          queue_id: String.t()
        ]

  @default_error_types [:error, :incorrect, :low_confidence, :contradiction]
  @default_min_confidence 0.0

  @doc """
  Loads samples from a Forge evaluation run and adds them to the CVL labeling queue.

  ## Options

  - `:error_types` - List of error types to include (default: all types)
  - `:max_samples` - Maximum number of samples to load (default: no limit)
  - `:min_confidence` - Minimum model confidence threshold (default: 0.0)
  - `:queue_id` - Override queue ID (default: CVL queue)

  ## Returns

  - `{:ok, count}` - Number of samples loaded
  - `{:error, reason}` - If loading fails

  ## Examples

      iex> {:ok, count} = MedlumLlm.CVL.SampleLoader.load_from_eval_run("eval_123")
      iex> count
      42

      iex> {:ok, count} = MedlumLlm.CVL.SampleLoader.load_from_eval_run(
      ...>   "eval_123",
      ...>   error_types: [:contradiction],
      ...>   max_samples: 50
      ...> )
  """
  @spec load_from_eval_run(String.t(), load_opts()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_from_eval_run(run_id, opts \\ []) do
    Logger.info("Loading samples from evaluation run: #{run_id}")

    with {:ok, forge_samples} <- fetch_forge_samples(run_id, opts),
         filtered_samples <- filter_samples(forge_samples, opts),
         anvil_samples <- transform_samples(filtered_samples, run_id),
         limited_samples <- apply_max_samples(anvil_samples, opts),
         :ok <- add_to_queue(limited_samples, opts) do
      Logger.info("Loaded #{length(limited_samples)} samples from #{run_id}")
      {:ok, length(limited_samples)}
    end
  end

  @doc """
  Loads samples from multiple evaluation runs.

  Combines samples from all runs, deduplicating by sample content hash.

  ## Examples

      iex> {:ok, count} = MedlumLlm.CVL.SampleLoader.load_from_eval_runs([
      ...>   "eval_20260125_1234",
      ...>   "eval_20260125_5678"
      ...> ])
  """
  @spec load_from_eval_runs([String.t()], load_opts()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def load_from_eval_runs(run_ids, opts \\ []) when is_list(run_ids) do
    results =
      Enum.map(run_ids, fn run_id ->
        case load_from_eval_run(run_id, opts) do
          {:ok, count} -> count
          {:error, _} = error -> error
        end
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      total = Enum.sum(results)
      {:ok, total}
    else
      {:error, {:partial_failure, errors}}
    end
  end

  @doc """
  Transforms a Forge sample into Anvil format.

  This is the core transformation function that maps Forge evaluation
  failures to NLI pairs suitable for human labeling.

  ## Examples

      iex> forge_sample = %{
      ...>   id: "forge_123",
      ...>   data: %{
      ...>     source_document: "Patient has diabetes...",
      ...>     generated_summary: "Patient is healthy...",
      ...>     error_type: :contradiction,
      ...>     model: "openbio_8b"
      ...>   }
      ...> }
      iex> anvil_sample = MedlumLlm.CVL.SampleLoader.transform_to_anvil_sample(forge_sample, "eval_123")
      iex> anvil_sample.metadata.source
      :eval_failure
  """
  @spec transform_to_anvil_sample(map(), String.t()) :: map()
  def transform_to_anvil_sample(forge_sample, eval_run_id) do
    data = forge_sample.data || forge_sample[:data] || %{}

    %{
      id: generate_sample_id(),
      premise: extract_premise(data),
      hypothesis: extract_hypothesis(data),
      metadata: %{
        source: :eval_failure,
        forge_sample_id: forge_sample.id || forge_sample[:id],
        eval_run_id: eval_run_id,
        model: data[:model] || data["model"],
        benchmark: data[:benchmark] || data["benchmark"],
        error_type: data[:error_type] || data["error_type"],
        confidence: data[:confidence] || data["confidence"],
        claim_type: extract_claim_type(data),
        created_at: DateTime.utc_now()
      }
    }
  end

  @doc """
  Creates a sample directly from premise and hypothesis text.

  Useful for creating samples outside of the Forge pipeline.

  ## Examples

      iex> sample = MedlumLlm.CVL.SampleLoader.create_sample(
      ...>   "Patient is diabetic with A1C of 9.2",
      ...>   "Patient has well-controlled blood sugar",
      ...>   error_type: :contradiction
      ...> )
  """
  @spec create_sample(String.t(), String.t(), keyword()) :: map()
  def create_sample(premise, hypothesis, opts \\ []) do
    %{
      id: generate_sample_id(),
      premise: premise,
      hypothesis: hypothesis,
      metadata: %{
        source: Keyword.get(opts, :source, :manual),
        error_type: Keyword.get(opts, :error_type),
        claim_type: Keyword.get(opts, :claim_type),
        model: Keyword.get(opts, :model),
        created_at: DateTime.utc_now()
      }
    }
  end

  # Private functions

  @spec fetch_forge_samples(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  defp fetch_forge_samples(run_id, opts) do
    error_types = Keyword.get(opts, :error_types, @default_error_types)

    # Try to fetch from Forge storage via the TrainingPipeline
    case fetch_from_storage(run_id, error_types) do
      {:ok, samples} when is_list(samples) ->
        {:ok, samples}

      {:error, :not_found} ->
        # Fall back to reading from file-based results
        fetch_from_results_file(run_id, error_types)

      error ->
        error
    end
  end

  defp fetch_from_storage(run_id, error_types) do
    # Try to use AuditedPostgres storage
    storage_opts = [pipeline_name: :cvl_training, run_id: run_id]

    with {:ok, storage_state} <- MedlumLlm.Storage.AuditedPostgres.init(storage_opts),
         {:ok, samples, _state} <-
           MedlumLlm.Storage.AuditedPostgres.list(
             [run_id: run_id, error_types: error_types],
             storage_state
           ) do
      {:ok, samples}
    else
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  defp fetch_from_results_file(run_id, error_types) do
    results_dir = get_results_dir()
    file_path = Path.join(results_dir, "#{run_id}.json")

    with {:ok, content} <- File.read(file_path),
         {:ok, data} <- Jason.decode(content, keys: :atoms) do
      samples =
        (data[:samples] || [])
        |> Enum.filter(fn sample ->
          error_type = sample[:data][:error_type] || sample[:error_type]
          error_type in error_types
        end)

      {:ok, samples}
    else
      {:error, :enoent} -> {:ok, []}
      error -> error
    end
  end

  defp filter_samples(samples, opts) do
    min_confidence = Keyword.get(opts, :min_confidence, @default_min_confidence)

    Enum.filter(samples, fn sample ->
      confidence = get_in(sample, [:data, :confidence]) || 1.0
      confidence >= min_confidence
    end)
  end

  defp transform_samples(forge_samples, run_id) do
    Enum.map(forge_samples, &transform_to_anvil_sample(&1, run_id))
  end

  defp apply_max_samples(samples, opts) do
    case Keyword.get(opts, :max_samples) do
      nil -> samples
      max when is_integer(max) -> Enum.take(samples, max)
    end
  end

  defp add_to_queue(samples, _opts) when samples == [], do: :ok

  defp add_to_queue(samples, _opts) do
    LabelingQueue.add_samples(samples)
  end

  defp generate_sample_id do
    random_bytes = :crypto.strong_rand_bytes(8)
    "cvl_" <> Base.encode16(random_bytes, case: :lower)
  end

  defp extract_premise(data) do
    # Try different field names that might contain the premise
    data[:premise] ||
      data["premise"] ||
      data[:source_document] ||
      data["source_document"] ||
      data[:source_text] ||
      data["source_text"] ||
      data[:context] ||
      data["context"] ||
      ""
  end

  defp extract_hypothesis(data) do
    # Try different field names that might contain the hypothesis
    data[:hypothesis] ||
      data["hypothesis"] ||
      data[:generated_summary] ||
      data["generated_summary"] ||
      data[:claim] ||
      data["claim"] ||
      data[:generated_text] ||
      data["generated_text"] ||
      ""
  end

  defp extract_claim_type(data) do
    # Look for claim type in various locations
    claim_type =
      get_in(data, [:nli_pairs, Access.at(0), :claim_type]) ||
        data[:claim_type] ||
        data["claim_type"]

    if claim_type, do: claim_type, else: :general
  end

  defp get_results_dir do
    Application.get_env(:medlum_llm, :eval_results_dir, "priv/eval_results")
  end
end
