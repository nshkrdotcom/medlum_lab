defmodule ClinicalNerEx.Telemetry do
  @moduledoc """
  Telemetry events for clinical_ner_ex.

  This module emits telemetry events for monitoring and observability.
  Attach your own handlers to receive these events.

  ## Events

  ### Extraction Events

  - `[:clinical_ner_ex, :extract, :start]` - Extraction started
    - Measurements: `%{system_time: integer()}`
    - Metadata: `%{method: atom(), entity_types: [atom()]}`

  - `[:clinical_ner_ex, :extract, :stop]` - Extraction completed
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{entity_count: integer(), method: atom()}`

  - `[:clinical_ner_ex, :extract, :exception]` - Extraction failed
    - Measurements: `%{duration: integer()}`
    - Metadata: `%{kind: atom(), reason: term()}`

  ### Linker Events

  - `[:clinical_ner_ex, :linker, :start]` - Ontology linking started
  - `[:clinical_ner_ex, :linker, :stop]` - Ontology linking completed
  - `[:clinical_ner_ex, :linker, :cache_hit]` - Cache hit for linking
  - `[:clinical_ner_ex, :linker, :cache_miss]` - Cache miss for linking

  ### Model Events

  - `[:clinical_ner_ex, :model, :load, :start]` - Model loading started
  - `[:clinical_ner_ex, :model, :load, :stop]` - Model loading completed
  - `[:clinical_ner_ex, :model, :inference, :start]` - Model inference started
  - `[:clinical_ner_ex, :model, :inference, :stop]` - Model inference completed

  ## Usage

  Attach your own handlers:

      :telemetry.attach(
        "my-handler",
        [:clinical_ner_ex, :extract, :stop],
        fn event, measurements, metadata, _config ->
          Logger.info("Extraction completed in \#{measurements.duration}ns")
        end,
        nil
      )

  Or use the default handlers for logging:

      ClinicalNerEx.Telemetry.setup()
  """

  require Logger

  @doc """
  Sets up default telemetry handlers for logging.

  Call this during application startup to enable default logging
  of telemetry events.
  """
  @spec setup() :: :ok
  def setup do
    events = [
      [:clinical_ner_ex, :extract, :start],
      [:clinical_ner_ex, :extract, :stop],
      [:clinical_ner_ex, :extract, :exception],
      [:clinical_ner_ex, :linker, :start],
      [:clinical_ner_ex, :linker, :stop],
      [:clinical_ner_ex, :linker, :cache_hit],
      [:clinical_ner_ex, :linker, :cache_miss]
    ]

    :telemetry.attach_many(
      "clinical-ner-handler",
      events,
      &handle_event/4,
      nil
    )

    :ok
  end

  @doc """
  Emits a telemetry event for extraction start.
  """
  @spec extraction_start(keyword()) :: :ok
  def extraction_start(metadata \\ []) do
    :telemetry.execute(
      [:clinical_ner_ex, :extract, :start],
      %{system_time: System.system_time()},
      Map.new(metadata)
    )
  end

  @doc """
  Emits a telemetry event for extraction stop.
  """
  @spec extraction_stop(integer(), keyword()) :: :ok
  def extraction_stop(duration, metadata \\ []) do
    :telemetry.execute(
      [:clinical_ner_ex, :extract, :stop],
      %{duration: duration},
      Map.new(metadata)
    )
  end

  @doc """
  Emits a telemetry event for extraction exception.
  """
  @spec extraction_exception(integer(), atom(), term()) :: :ok
  def extraction_exception(duration, kind, reason) do
    :telemetry.execute(
      [:clinical_ner_ex, :extract, :exception],
      %{duration: duration},
      %{kind: kind, reason: reason}
    )
  end

  @doc """
  Emits a telemetry event for linker cache hit.
  """
  @spec linker_cache_hit(keyword()) :: :ok
  def linker_cache_hit(metadata \\ []) do
    :telemetry.execute(
      [:clinical_ner_ex, :linker, :cache_hit],
      %{},
      Map.new(metadata)
    )
  end

  @doc """
  Emits a telemetry event for linker cache miss.
  """
  @spec linker_cache_miss(keyword()) :: :ok
  def linker_cache_miss(metadata \\ []) do
    :telemetry.execute(
      [:clinical_ner_ex, :linker, :cache_miss],
      %{},
      Map.new(metadata)
    )
  end

  @doc """
  Executes a function with telemetry span tracking.

  ## Examples

      ClinicalNerEx.Telemetry.span([:clinical_ner_ex, :extract], %{method: :hybrid}, fn ->
        # extraction logic
        {result, %{entity_count: 5}}
      end)
  """
  @spec span([atom()], map(), (-> {term(), map()})) :: term()
  def span(event_prefix, start_metadata, fun) when is_function(fun, 0) do
    :telemetry.span(event_prefix, start_metadata, fun)
  end

  # Private handler implementations

  defp handle_event([:clinical_ner_ex, :extract, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements[:duration], :native, :millisecond)

    Logger.debug(
      "Extraction completed: method=#{metadata[:method]}, entities=#{metadata[:entity_count]}, duration=#{duration_ms}ms"
    )
  end

  defp handle_event([:clinical_ner_ex, :extract, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements[:duration], :native, :millisecond)

    Logger.warning(
      "Extraction failed: kind=#{metadata[:kind]}, reason=#{inspect(metadata[:reason])}, duration=#{duration_ms}ms"
    )
  end

  defp handle_event([:clinical_ner_ex, :linker, :cache_hit], _measurements, metadata, _config) do
    Logger.debug("Linker cache hit: entity_type=#{metadata[:entity_type]}")
  end

  defp handle_event([:clinical_ner_ex, :linker, :cache_miss], _measurements, metadata, _config) do
    Logger.debug("Linker cache miss: entity_type=#{metadata[:entity_type]}")
  end

  defp handle_event(_event, _measurements, _metadata, _config), do: :ok
end
