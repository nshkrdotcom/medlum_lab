defmodule ClinicalNerEx.Pipeline.Coordinator do
  @moduledoc """
  Coordinates parallel entity extraction across extractors.

  The coordinator manages the parallel execution of multiple entity extractors,
  collecting results and handling timeouts gracefully.

  ## Extraction Flow

  1. Build extraction context from preprocessed text
  2. Launch extractors in parallel based on requested entity types
  3. Collect results with timeout handling
  4. Return flattened list of all extracted entities

  ## Examples

      preprocessed = %{
        normalized: "Patient on metformin 500mg",
        sentences: ["Patient on metformin 500mg"]
      }

      {:ok, entities} = Coordinator.extract(preprocessed, :rule_based, [:medication], 500)
  """

  require Logger

  alias ClinicalNerEx.Extractors.{Medication, LabValue, Diagnosis, Procedure, Temporal}

  @extractors %{
    medication: Medication,
    lab_value: LabValue,
    diagnosis: Diagnosis,
    procedure: Procedure,
    temporal: Temporal
  }

  @doc """
  Run extraction for specified entity types.

  Launches extractors in parallel and collects results within the specified timeout.

  ## Parameters

  - `preprocessed` - Map containing normalized text and sentences
  - `method` - Extraction method (:rule_based, :transformer, :hybrid)
  - `entity_types` - List of entity types to extract
  - `timeout_ms` - Timeout in milliseconds for each extractor

  ## Returns

  - `{:ok, [Entity.t()]}` - List of extracted entities
  - `{:error, reason}` - Error tuple on failure

  ## Examples

      iex> preprocessed = %{normalized: "metformin 500mg", sentences: ["metformin 500mg"]}
      iex> {:ok, entities} = Coordinator.extract(preprocessed, :rule_based, [:medication], 500)
      iex> is_list(entities)
      true
  """
  @spec extract(map(), atom(), [atom()], pos_integer()) ::
          {:ok, [ClinicalNerEx.Entity.t()]} | {:error, term()}
  def extract(preprocessed, method, entity_types, timeout_ms) do
    context = build_context(preprocessed, method)

    # Launch extractors in parallel
    tasks =
      entity_types
      |> Enum.map(fn type ->
        case Map.get(@extractors, type) do
          nil ->
            Logger.warning("Unknown entity type: #{type}")
            nil

          extractor ->
            Task.async(fn ->
              {type, run_extractor(extractor, context)}
            end)
        end
      end)
      |> Enum.filter(& &1)

    # Collect results with timeout
    results =
      Task.yield_many(tasks, timeout_ms)
      |> Enum.flat_map(fn
        {_task, {:ok, {_type, {:ok, entities}}}} ->
          entities

        {task, nil} ->
          # Task timed out
          Logger.warning("Extraction task timed out")
          Task.shutdown(task, :brutal_kill)
          []

        {_task, {:ok, {type, {:error, reason}}}} ->
          Logger.warning("Extractor #{type} failed: #{inspect(reason)}")
          []

        {_task, {:exit, reason}} ->
          Logger.warning("Extraction task crashed: #{inspect(reason)}")
          []
      end)

    {:ok, results}
  rescue
    e ->
      Logger.error("Coordinator extraction failed: #{Exception.message(e)}")
      {:error, {:coordinator_failed, Exception.message(e)}}
  end

  @doc """
  Returns the available extractors mapping.

  ## Examples

      iex> extractors = Coordinator.extractors()
      iex> Map.has_key?(extractors, :medication)
      true
  """
  @spec extractors() :: map()
  def extractors, do: @extractors

  @doc """
  Checks if an entity type is supported.

  ## Examples

      iex> Coordinator.supported_type?(:medication)
      true

      iex> Coordinator.supported_type?(:invalid)
      false
  """
  @spec supported_type?(atom()) :: boolean()
  def supported_type?(type), do: Map.has_key?(@extractors, type)

  # Private functions

  defp build_context(preprocessed, method) do
    %{
      text: preprocessed.normalized,
      sentences: preprocessed.sentences,
      tokens: nil,
      method: method,
      opts: []
    }
  end

  defp run_extractor(extractor, context) do
    # Ensure the extractor is available
    if Code.ensure_loaded?(extractor) and function_exported?(extractor, :extract, 1) do
      extractor.extract(context)
    else
      Logger.warning("Extractor #{extractor} not available")
      {:ok, []}
    end
  end
end
