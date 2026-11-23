defmodule MedlumLlm.Telemetry.Events do
  @moduledoc """
  Medical AI event definitions for telemetry.

  This module provides a centralized registry of medical AI telemetry events
  for MedlumLlm and related medical NLP applications. Events cover:

  - **Evaluation events**: Benchmark runs and sample evaluations
  - **CVL events**: Clinical Verification Layer hallucination detection
  - **Document events**: Clinical document processing

  ## Event Naming Convention

  Events follow the telemetry convention: `[app, domain, action, phase]`

  - Prefix: `:medlum_llm`
  - Domain: `:eval`, `:cvl`, `:document`
  - Action: specific operation
  - Phase: `:start`, `:stop`, `:exception`

  ## Usage

  ```elixir
  # Get all medical events
  events = MedlumLlm.Telemetry.Events.medical_events()

  # Get specific category
  eval_events = MedlumLlm.Telemetry.Events.evaluation_events()
  cvl_events = MedlumLlm.Telemetry.Events.cvl_events()

  # Get event description
  desc = MedlumLlm.Telemetry.Events.event_description([:medlum_llm, :cvl, :verification, :stop])
  # => "CVL verification completed with verdict and agent consensus"
  ```
  """

  @typedoc "A telemetry event name as a list of atoms"
  @type event_name :: [atom()]

  @typedoc "Medical event category identifier"
  @type category :: :evaluation | :cvl | :document

  # Evaluation events - benchmark runs and sample evaluations
  @evaluation_events [
    [:medlum_llm, :eval, :run, :start],
    [:medlum_llm, :eval, :run, :stop],
    [:medlum_llm, :eval, :sample, :start],
    [:medlum_llm, :eval, :sample, :stop],
    [:medlum_llm, :eval, :sample, :exception]
  ]

  # CVL (Clinical Verification Layer) events
  @cvl_events [
    [:medlum_llm, :cvl, :verification, :start],
    [:medlum_llm, :cvl, :verification, :stop],
    [:medlum_llm, :cvl, :agent, :medication, :stop],
    [:medlum_llm, :cvl, :agent, :lab, :stop],
    [:medlum_llm, :cvl, :agent, :ontology, :stop],
    [:medlum_llm, :cvl, :agent, :temporal, :stop],
    [:medlum_llm, :cvl, :agent, :differential, :stop]
  ]

  # Document processing events
  @document_events [
    [:medlum_llm, :document, :process, :start],
    [:medlum_llm, :document, :process, :stop],
    [:medlum_llm, :document, :summarize, :stop],
    [:medlum_llm, :document, :extract, :stop]
  ]

  # All medical events combined
  @medical_events @evaluation_events ++ @cvl_events ++ @document_events

  # Event descriptions
  @event_descriptions %{
    # Evaluation events
    [:medlum_llm, :eval, :run, :start] =>
      "Evaluation run started with benchmark configuration",
    [:medlum_llm, :eval, :run, :stop] =>
      "Evaluation run completed with final statistics",
    [:medlum_llm, :eval, :sample, :start] =>
      "Individual sample evaluation started",
    [:medlum_llm, :eval, :sample, :stop] =>
      "Individual sample evaluation completed with prediction result",
    [:medlum_llm, :eval, :sample, :exception] =>
      "Sample evaluation failed with error or timeout",

    # CVL events
    [:medlum_llm, :cvl, :verification, :start] =>
      "CVL verification started for a claim",
    [:medlum_llm, :cvl, :verification, :stop] =>
      "CVL verification completed with verdict and agent consensus",
    [:medlum_llm, :cvl, :agent, :medication, :stop] =>
      "Medication agent (RxNorm) verification completed",
    [:medlum_llm, :cvl, :agent, :lab, :stop] =>
      "Lab agent (LOINC) verification completed",
    [:medlum_llm, :cvl, :agent, :ontology, :stop] =>
      "Ontology agent (SNOMED-CT/ICD-10) verification completed",
    [:medlum_llm, :cvl, :agent, :temporal, :stop] =>
      "Temporal agent (timeline consistency) verification completed",
    [:medlum_llm, :cvl, :agent, :differential, :stop] =>
      "Differential diagnosis agent verification completed",

    # Document events
    [:medlum_llm, :document, :process, :start] =>
      "Document processing started",
    [:medlum_llm, :document, :process, :stop] =>
      "Document processing completed with extracted entities",
    [:medlum_llm, :document, :summarize, :stop] =>
      "Document summarization completed",
    [:medlum_llm, :document, :extract, :stop] =>
      "Entity extraction completed from document"
  }

  @doc """
  Returns all medical telemetry events.

  ## Examples

      iex> events = MedlumLlm.Telemetry.Events.medical_events()
      iex> [:medlum_llm, :eval, :sample, :stop] in events
      true
      iex> [:medlum_llm, :cvl, :verification, :stop] in events
      true
  """
  @spec medical_events() :: [event_name()]
  def medical_events, do: @medical_events

  @doc """
  Returns evaluation-related events.

  These events track medical benchmark evaluation runs and individual sample evaluations.

  ## Events

  - `[:medlum_llm, :eval, :run, :start]` - Evaluation run started
  - `[:medlum_llm, :eval, :run, :stop]` - Evaluation run completed
  - `[:medlum_llm, :eval, :sample, :start]` - Sample evaluation started
  - `[:medlum_llm, :eval, :sample, :stop]` - Sample evaluation completed
  - `[:medlum_llm, :eval, :sample, :exception]` - Sample evaluation failed

  ## Examples

      iex> events = MedlumLlm.Telemetry.Events.evaluation_events()
      iex> length(events)
      5
      iex> [:medlum_llm, :eval, :sample, :stop] in events
      true
  """
  @spec evaluation_events() :: [event_name()]
  def evaluation_events, do: @evaluation_events

  @doc """
  Returns CVL (Clinical Verification Layer) events.

  These events track hallucination detection through the 5-agent verification system:
  - Medication Agent (RxNorm)
  - Lab Agent (LOINC)
  - Ontology Agent (SNOMED-CT/ICD-10)
  - Temporal Agent (timeline consistency)
  - Differential Diagnosis Agent

  ## Events

  - `[:medlum_llm, :cvl, :verification, :start]` - Verification started
  - `[:medlum_llm, :cvl, :verification, :stop]` - Verification completed with consensus
  - `[:medlum_llm, :cvl, :agent, :medication, :stop]` - Medication agent completed
  - `[:medlum_llm, :cvl, :agent, :lab, :stop]` - Lab agent completed
  - `[:medlum_llm, :cvl, :agent, :ontology, :stop]` - Ontology agent completed
  - `[:medlum_llm, :cvl, :agent, :temporal, :stop]` - Temporal agent completed
  - `[:medlum_llm, :cvl, :agent, :differential, :stop]` - Differential agent completed

  ## Examples

      iex> events = MedlumLlm.Telemetry.Events.cvl_events()
      iex> length(events)
      7
      iex> [:medlum_llm, :cvl, :verification, :stop] in events
      true
  """
  @spec cvl_events() :: [event_name()]
  def cvl_events, do: @cvl_events

  @doc """
  Returns document processing events.

  These events track clinical document processing including summarization and extraction.

  ## Events

  - `[:medlum_llm, :document, :process, :start]` - Processing started
  - `[:medlum_llm, :document, :process, :stop]` - Processing completed
  - `[:medlum_llm, :document, :summarize, :stop]` - Summarization completed
  - `[:medlum_llm, :document, :extract, :stop]` - Extraction completed

  ## Examples

      iex> events = MedlumLlm.Telemetry.Events.document_events()
      iex> length(events)
      4
      iex> [:medlum_llm, :document, :process, :stop] in events
      true
  """
  @spec document_events() :: [event_name()]
  def document_events, do: @document_events

  @doc """
  Returns events organized by category.

  ## Categories

  - `:evaluation` - Benchmark and sample evaluation events
  - `:cvl` - Clinical Verification Layer events
  - `:document` - Document processing events

  ## Examples

      iex> categories = MedlumLlm.Telemetry.Events.events_by_category()
      iex> Map.keys(categories) |> Enum.sort()
      [:cvl, :document, :evaluation]
  """
  @spec events_by_category() :: %{category() => [event_name()]}
  def events_by_category do
    %{
      evaluation: @evaluation_events,
      cvl: @cvl_events,
      document: @document_events
    }
  end

  @doc """
  Returns the description for a medical event.

  Returns `nil` if the event is not a known medical event.

  ## Parameters

  - `event_name` - The telemetry event name (list of atoms)

  ## Examples

      iex> MedlumLlm.Telemetry.Events.event_description([:medlum_llm, :cvl, :verification, :stop])
      "CVL verification completed with verdict and agent consensus"

      iex> MedlumLlm.Telemetry.Events.event_description([:unknown, :event])
      nil
  """
  @spec event_description(event_name()) :: String.t() | nil
  def event_description(event_name) do
    Map.get(@event_descriptions, event_name)
  end

  @doc """
  Returns the category for a medical event.

  Returns `nil` if the event is not a known medical event.

  ## Examples

      iex> MedlumLlm.Telemetry.Events.event_category([:medlum_llm, :eval, :sample, :stop])
      :evaluation

      iex> MedlumLlm.Telemetry.Events.event_category([:medlum_llm, :cvl, :verification, :stop])
      :cvl

      iex> MedlumLlm.Telemetry.Events.event_category([:unknown, :event])
      nil
  """
  @spec event_category(event_name()) :: category() | nil
  def event_category(event_name) do
    cond do
      event_name in @evaluation_events -> :evaluation
      event_name in @cvl_events -> :cvl
      event_name in @document_events -> :document
      true -> nil
    end
  end

  @doc """
  Returns information about a medical event including category and description.

  Returns `nil` if the event is not a known medical event.

  ## Examples

      iex> info = MedlumLlm.Telemetry.Events.event_info([:medlum_llm, :eval, :sample, :stop])
      iex> info.category
      :evaluation
      iex> info.description
      "Individual sample evaluation completed with prediction result"

      iex> MedlumLlm.Telemetry.Events.event_info([:unknown, :event])
      nil
  """
  @spec event_info(event_name()) :: %{category: category(), description: String.t()} | nil
  def event_info(event_name) do
    case {event_category(event_name), event_description(event_name)} do
      {nil, _} -> nil
      {_, nil} -> nil
      {category, description} -> %{category: category, description: description}
    end
  end

  @doc """
  Checks if an event name is a known medical event.

  ## Examples

      iex> MedlumLlm.Telemetry.Events.medical_event?([:medlum_llm, :eval, :sample, :stop])
      true

      iex> MedlumLlm.Telemetry.Events.medical_event?([:req_llm, :request, :stop])
      false
  """
  @spec medical_event?(event_name()) :: boolean()
  def medical_event?(event_name) do
    event_name in @medical_events
  end
end
