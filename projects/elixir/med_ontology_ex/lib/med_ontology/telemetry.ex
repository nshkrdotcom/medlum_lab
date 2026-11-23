defmodule MedOntology.Telemetry do
  @moduledoc """
  Telemetry events for med_ontology_ex.

  This module defines and attaches telemetry event handlers for monitoring
  the performance and behavior of the library.

  ## Events

  The following telemetry events are emitted:

  ### Lookup Events

    * `[:med_ontology, :lookup, :start]` - Emitted when a lookup begins
      * Metadata: `%{ontology: atom(), code: String.t()}`

    * `[:med_ontology, :lookup, :stop]` - Emitted when a lookup completes
      * Measurements: `%{duration: integer()}`
      * Metadata: `%{ontology: atom(), code: String.t(), cache_hit: boolean()}`

    * `[:med_ontology, :lookup, :exception]` - Emitted when a lookup fails
      * Measurements: `%{duration: integer()}`
      * Metadata: `%{ontology: atom(), code: String.t(), kind: atom(), reason: term()}`

  ### Search Events

    * `[:med_ontology, :search, :start]` - Emitted when a search begins
      * Metadata: `%{ontology: atom(), query: String.t()}`

    * `[:med_ontology, :search, :stop]` - Emitted when a search completes
      * Measurements: `%{duration: integer(), result_count: integer()}`
      * Metadata: `%{ontology: atom(), query: String.t()}`

  ### Cache Events

    * `[:med_ontology, :cache, :hit]` - Emitted on cache hit
      * Metadata: `%{ontology: atom(), key: String.t()}`

    * `[:med_ontology, :cache, :miss]` - Emitted on cache miss
      * Metadata: `%{ontology: atom(), key: String.t()}`

  ### API Events

    * `[:med_ontology, :api, :request]` - Emitted for each API request
      * Measurements: `%{duration: integer()}`
      * Metadata: `%{client: atom(), endpoint: String.t(), status: integer()}`

  ## Usage

  You can attach your own handlers to these events:

      :telemetry.attach(
        "my-handler",
        [:med_ontology, :lookup, :stop],
        fn event, measurements, metadata, config ->
          # Handle the event
        end,
        nil
      )

  """

  require Logger

  @events [
    [:med_ontology, :lookup, :start],
    [:med_ontology, :lookup, :stop],
    [:med_ontology, :lookup, :exception],
    [:med_ontology, :search, :start],
    [:med_ontology, :search, :stop],
    [:med_ontology, :cache, :hit],
    [:med_ontology, :cache, :miss],
    [:med_ontology, :api, :request]
  ]

  @doc """
  Sets up telemetry event handlers.

  This is called automatically when the application starts.
  """
  @spec setup() :: :ok
  def setup do
    :telemetry.attach_many(
      "med-ontology-handler",
      @events,
      &handle_event/4,
      nil
    )

    :ok
  end

  @doc """
  Returns the list of telemetry events emitted by this library.
  """
  @spec events() :: [list()]
  def events, do: @events

  @doc """
  Executes a span for measuring lookup operations.

  ## Examples

      MedOntology.Telemetry.span(:lookup, %{ontology: :snomed_ct, code: "44054006"}, fn ->
        # perform lookup
        {:ok, concept}
      end)

  """
  @spec span(atom(), map(), (-> result)) :: result when result: var
  def span(operation, metadata, fun) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:med_ontology, operation, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:med_ontology, operation, :stop],
        %{duration: duration},
        Map.put(metadata, :result, :ok)
      )

      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:med_ontology, operation, :exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: e})
        )

        reraise e, __STACKTRACE__
    end
  end

  # Event handlers

  defp handle_event([:med_ontology, :lookup, :stop], measurements, metadata, _config) do
    Logger.debug(
      "[MedOntology] Lookup completed - ontology=#{metadata[:ontology]} code=#{metadata[:code]} " <>
        "duration_ms=#{System.convert_time_unit(measurements[:duration], :native, :millisecond)} " <>
        "cache_hit=#{metadata[:cache_hit]}"
    )
  end

  defp handle_event([:med_ontology, :lookup, :exception], measurements, metadata, _config) do
    Logger.warning(
      "[MedOntology] Lookup failed - ontology=#{metadata[:ontology]} code=#{metadata[:code]} " <>
        "duration_ms=#{System.convert_time_unit(measurements[:duration], :native, :millisecond)} " <>
        "error=#{inspect(metadata[:reason])}"
    )
  end

  defp handle_event([:med_ontology, :search, :stop], measurements, metadata, _config) do
    Logger.debug(
      "[MedOntology] Search completed - ontology=#{metadata[:ontology]} query=#{metadata[:query]} " <>
        "duration_ms=#{System.convert_time_unit(measurements[:duration], :native, :millisecond)} " <>
        "results=#{measurements[:result_count]}"
    )
  end

  defp handle_event([:med_ontology, :cache, :hit], _measurements, metadata, _config) do
    Logger.debug("[MedOntology] Cache hit - ontology=#{metadata[:ontology]} key=#{metadata[:key]}")
  end

  defp handle_event([:med_ontology, :cache, :miss], _measurements, metadata, _config) do
    Logger.debug("[MedOntology] Cache miss - ontology=#{metadata[:ontology]} key=#{metadata[:key]}")
  end

  defp handle_event([:med_ontology, :api, :request], measurements, metadata, _config) do
    Logger.debug(
      "[MedOntology] API request - client=#{metadata[:client]} endpoint=#{metadata[:endpoint]} " <>
        "status=#{metadata[:status]} " <>
        "duration_ms=#{System.convert_time_unit(measurements[:duration], :native, :millisecond)}"
    )
  end

  defp handle_event(_event, _measurements, _metadata, _config), do: :ok
end
