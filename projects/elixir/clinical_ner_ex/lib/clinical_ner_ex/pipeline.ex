defmodule ClinicalNerEx.Pipeline do
  @moduledoc """
  Orchestrates the clinical NER extraction pipeline.

  The pipeline follows these stages:

  1. **Preprocessing**: Text normalization, sentence segmentation
  2. **Extraction**: Parallel entity extraction using configured extractors
  3. **Postprocessing**: Entity merging, deduplication, confidence adjustment
  4. **Linking**: Ontology code assignment via med_ontology_ex

  ## Usage

      {:ok, entities} = ClinicalNerEx.Pipeline.extract(text, method: :hybrid)

  ## Options

  - `:method` - Extraction method (`:rule_based`, `:transformer`, `:hybrid`)
  - `:entity_types` - List of entity types to extract
  - `:confidence_threshold` - Minimum confidence to include
  - `:link_ontologies` - Whether to perform ontology linking (default: true)
  - `:timeout_ms` - Timeout for extraction (default: 500)
  """

  require Logger

  alias ClinicalNerEx.{Entity, Config, Linker, Telemetry}
  alias ClinicalNerEx.Pipeline.{Preprocessor, Coordinator, Postprocessor}

  @type extraction_opts :: [
          method: :rule_based | :transformer | :hybrid,
          entity_types: [Entity.entity_type()],
          confidence_threshold: float(),
          link_ontologies: boolean(),
          timeout_ms: pos_integer()
        ]

  @default_entity_types [:medication, :lab_value, :diagnosis, :procedure, :temporal]

  @doc """
  Execute the full extraction pipeline.

  ## Options

  - `:method` - Extraction method (`:rule_based`, `:transformer`, `:hybrid`)
  - `:entity_types` - List of entity types to extract
  - `:confidence_threshold` - Minimum confidence to include
  - `:link_ontologies` - Whether to perform ontology linking (default: true)
  - `:timeout_ms` - Timeout for extraction (default: 500)

  ## Examples

      iex> {:ok, entities} = ClinicalNerEx.Pipeline.extract("Patient on metformin 500mg BID")
      iex> is_list(entities)
      true
  """
  @spec extract(String.t(), extraction_opts()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract(text, opts \\ []) when is_binary(text) do
    start_time = System.monotonic_time()
    method = Keyword.get(opts, :method, Config.default_method())
    entity_types = Keyword.get(opts, :entity_types, @default_entity_types)
    confidence_threshold = Keyword.get(opts, :confidence_threshold, 0.7)
    link_ontologies = Keyword.get(opts, :link_ontologies, Config.enable_ontology_linking?())
    timeout_ms = Keyword.get(opts, :timeout_ms, Config.extraction_timeout_ms())

    Telemetry.extraction_start(method: method, entity_types: entity_types)

    try do
      result =
        with {:ok, preprocessed} <- Preprocessor.process(text),
             {:ok, entities} <- Coordinator.extract(preprocessed, method, entity_types, timeout_ms),
             {:ok, merged} <- Postprocessor.process(entities, confidence_threshold),
             {:ok, linked} <- maybe_link(merged, link_ontologies) do
          {:ok, linked}
        end

      duration = System.monotonic_time() - start_time
      entity_count = case result do
        {:ok, entities} -> length(entities)
        _ -> 0
      end

      Telemetry.extraction_stop(duration, method: method, entity_count: entity_count)

      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time
        Telemetry.extraction_exception(duration, :error, e)
        {:error, {:extraction_failed, Exception.message(e)}}
    end
  end

  @doc """
  Execute extraction on multiple texts in parallel.

  ## Examples

      iex> texts = ["Patient on aspirin", "Labs show A1c 6.5%"]
      iex> {:ok, results} = ClinicalNerEx.Pipeline.extract_batch(texts)
      iex> length(results) == length(texts)
      true
  """
  @spec extract_batch([String.t()], extraction_opts()) :: {:ok, [[Entity.t()]]} | {:error, term()}
  def extract_batch(texts, opts \\ []) when is_list(texts) do
    timeout = Keyword.get(opts, :batch_timeout, 30_000)

    results =
      Task.async_stream(
        texts,
        fn text -> extract(text, opts) end,
        timeout: timeout,
        max_concurrency: System.schedulers_online()
      )
      |> Enum.map(fn
        {:ok, {:ok, entities}} -> entities
        {:ok, {:error, _}} -> []
        {:exit, _reason} -> []
      end)

    {:ok, results}
  end

  @doc """
  Stream extraction for large document sets.

  Returns a stream that yields extraction results.

  ## Examples

      texts
      |> ClinicalNerEx.Pipeline.extract_stream()
      |> Enum.take(10)
  """
  @spec extract_stream(Enumerable.t(), extraction_opts()) :: Enumerable.t()
  def extract_stream(texts, opts \\ []) do
    Stream.map(texts, fn text ->
      case extract(text, opts) do
        {:ok, entities} -> entities
        {:error, _} -> []
      end
    end)
  end

  @doc """
  Returns the default entity types that will be extracted.
  """
  @spec default_entity_types() :: [Entity.entity_type()]
  def default_entity_types, do: @default_entity_types

  # Private functions

  defp maybe_link(entities, true), do: Linker.link_all(entities)
  defp maybe_link(entities, false), do: {:ok, entities}
end
