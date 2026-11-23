defmodule MedlumLlm.Metrics.Telemetry do
  @moduledoc """
  Standard telemetry event definitions for medical AI systems.

  This module provides standardized telemetry event handling for MedlumLlm
  and other medical AI applications. It defines event specifications and
  provides functions to attach/detach handlers for all medical events.

  ## Event Hierarchy

  ### Evaluation Events
  - `[:medlum_llm, :eval, :run, :start]` - Evaluation run initiated
  - `[:medlum_llm, :eval, :run, :stop]` - Evaluation run completed
  - `[:medlum_llm, :eval, :sample, :stop]` - Sample processed successfully
  - `[:medlum_llm, :eval, :sample, :exception]` - Sample processing failed

  ### CVL Events
  - `[:medlum_llm, :cvl, :verify, :stop]` - CVL verification completed
  - `[:medlum_llm, :cvl, :agent, :verdict]` - Individual agent verdict rendered
  - `[:medlum_llm, :cvl, :consensus, :complete]` - Multi-agent consensus reached

  ### Inference Events
  - `[:medlum_llm, :chat, :complete]` - Chat completion finished
  - `[:medlum_llm, :embed, :complete]` - Embedding generation finished

  ## Usage

      # Attach handlers at application startup
      MedlumLlm.Metrics.Telemetry.attach_all()

      # With custom handler ID
      MedlumLlm.Metrics.Telemetry.attach_all(handler_id: :my_medical_metrics)

      # Detach when needed
      MedlumLlm.Metrics.Telemetry.detach_all()
  """

  require Logger

  alias MetricsEx.TelemetryHandler

  @handler_id :medlum_llm_metrics

  # Event type specifications for each medical telemetry event
  @eval_events [
    {[:medlum_llm, :eval, :run, :start], :counter},
    {[:medlum_llm, :eval, :run, :stop], :histogram},
    {[:medlum_llm, :eval, :sample, :stop], :histogram},
    {[:medlum_llm, :eval, :sample, :exception], :counter}
  ]

  @cvl_events [
    {[:medlum_llm, :cvl, :verify, :stop], :histogram},
    {[:medlum_llm, :cvl, :agent, :verdict], :histogram},
    {[:medlum_llm, :cvl, :consensus, :complete], :histogram}
  ]

  @inference_events [
    {[:medlum_llm, :chat, :complete], :histogram},
    {[:medlum_llm, :embed, :complete], :histogram}
  ]

  @doc """
  Returns all medical telemetry event specifications.

  Each event is a tuple of `{event_name, metric_type}` where:
  - `event_name` is a list of atoms representing the telemetry event path
  - `metric_type` is `:counter`, `:gauge`, or `:histogram`

  ## Examples

      iex> MedlumLlm.Metrics.Telemetry.all_events()
      [
        {[:medlum_llm, :eval, :run, :start], :counter},
        {[:medlum_llm, :eval, :run, :stop], :histogram},
        ...
      ]
  """
  @spec all_events() :: list({list(atom()), atom()})
  def all_events do
    @eval_events ++ @cvl_events ++ @inference_events
  end

  @doc """
  Returns evaluation-related telemetry event specifications.
  """
  @spec eval_events() :: list({list(atom()), atom()})
  def eval_events, do: @eval_events

  @doc """
  Returns CVL-related telemetry event specifications.
  """
  @spec cvl_events() :: list({list(atom()), atom()})
  def cvl_events, do: @cvl_events

  @doc """
  Returns inference-related telemetry event specifications.
  """
  @spec inference_events() :: list({list(atom()), atom()})
  def inference_events, do: @inference_events

  @doc """
  Attaches MetricsEx to all medical telemetry events.

  This function attaches handlers for evaluation, CVL, and inference events
  so that telemetry emissions are automatically recorded as metrics.

  ## Options

    - `:handler_id` - Custom handler ID (default: `:medlum_llm_metrics`)
    - `:events` - List of event categories to attach (default: all)
      Valid categories: `:eval`, `:cvl`, `:inference`, `:all`

  ## Examples

      # Attach all medical event handlers
      MedlumLlm.Metrics.Telemetry.attach_all()

      # Attach with custom handler ID
      MedlumLlm.Metrics.Telemetry.attach_all(handler_id: :custom_medical_handler)

      # Attach only CVL events
      MedlumLlm.Metrics.Telemetry.attach_all(events: [:cvl])

      # Attach evaluation and inference events
      MedlumLlm.Metrics.Telemetry.attach_all(events: [:eval, :inference])
  """
  @spec attach_all(keyword()) :: :ok
  def attach_all(opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, @handler_id)
    event_categories = Keyword.get(opts, :events, [:all])

    events = build_event_list(event_categories)

    TelemetryHandler.attach_telemetry(events, handler_id: handler_id)

    Logger.info("Attached MedlumLlm.Metrics.Telemetry to #{length(events)} events")
    :ok
  end

  @doc """
  Detaches MetricsEx from all medical telemetry events.

  ## Options

    - `:handler_id` - Handler ID to detach (default: `:medlum_llm_metrics`)

  ## Examples

      # Detach default handler
      MedlumLlm.Metrics.Telemetry.detach_all()

      # Detach custom handler
      MedlumLlm.Metrics.Telemetry.detach_all(handler_id: :custom_medical_handler)
  """
  @spec detach_all(keyword()) :: :ok | {:error, :not_found}
  def detach_all(opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, @handler_id)
    TelemetryHandler.detach_telemetry(handler_id)
  end

  @doc """
  Checks if medical telemetry handlers are attached.

  ## Examples

      iex> MedlumLlm.Metrics.Telemetry.attached?()
      true
  """
  @spec attached?(keyword()) :: boolean()
  def attached?(opts \\ []) do
    handler_id = Keyword.get(opts, :handler_id, @handler_id)

    :telemetry.list_handlers([])
    |> Enum.any?(fn handler -> handler.id == handler_id end)
  end

  # Private functions

  defp build_event_list(categories) do
    categories
    |> List.wrap()
    |> Enum.flat_map(&events_for_category/1)
    |> Enum.uniq()
  end

  defp events_for_category(:all), do: all_events()
  defp events_for_category(:eval), do: @eval_events
  defp events_for_category(:cvl), do: @cvl_events
  defp events_for_category(:inference), do: @inference_events
  defp events_for_category(_unknown), do: []
end
