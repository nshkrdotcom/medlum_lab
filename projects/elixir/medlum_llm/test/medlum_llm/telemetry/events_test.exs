defmodule MedlumLlm.Telemetry.EventsTest do
  @moduledoc """
  Tests for the MedlumLlm.Telemetry.Events module.
  """
  use ExUnit.Case, async: true

  alias MedlumLlm.Telemetry.Events

  describe "medical_events/0" do
    test "returns a list of telemetry event names" do
      events = Events.medical_events()

      assert is_list(events)
      refute Enum.empty?(events)

      # All events should be lists of atoms
      Enum.each(events, fn event ->
        assert is_list(event)
        assert Enum.all?(event, &is_atom/1)
      end)
    end

    test "includes all expected event categories" do
      events = Events.medical_events()

      # Evaluation events
      assert [:medlum_llm, :eval, :run, :start] in events
      assert [:medlum_llm, :eval, :sample, :stop] in events

      # CVL events
      assert [:medlum_llm, :cvl, :verification, :start] in events
      assert [:medlum_llm, :cvl, :verification, :stop] in events

      # Document events
      assert [:medlum_llm, :document, :process, :stop] in events
    end

    test "returns exactly 16 medical events" do
      events = Events.medical_events()
      assert length(events) == 16
    end
  end

  describe "evaluation_events/0" do
    test "returns only evaluation-related events" do
      events = Events.evaluation_events()

      assert is_list(events)
      assert length(events) == 5

      Enum.each(events, fn [prefix, domain | _rest] ->
        assert prefix == :medlum_llm
        assert domain == :eval
      end)
    end

    test "includes all expected evaluation events" do
      events = Events.evaluation_events()

      assert [:medlum_llm, :eval, :run, :start] in events
      assert [:medlum_llm, :eval, :run, :stop] in events
      assert [:medlum_llm, :eval, :sample, :start] in events
      assert [:medlum_llm, :eval, :sample, :stop] in events
      assert [:medlum_llm, :eval, :sample, :exception] in events
    end
  end

  describe "cvl_events/0" do
    test "returns only CVL-related events" do
      events = Events.cvl_events()

      assert is_list(events)
      assert length(events) == 7

      Enum.each(events, fn [prefix, domain | _rest] ->
        assert prefix == :medlum_llm
        assert domain == :cvl
      end)
    end

    test "includes verification events" do
      events = Events.cvl_events()

      assert [:medlum_llm, :cvl, :verification, :start] in events
      assert [:medlum_llm, :cvl, :verification, :stop] in events
    end

    test "includes all agent events" do
      events = Events.cvl_events()

      assert [:medlum_llm, :cvl, :agent, :medication, :stop] in events
      assert [:medlum_llm, :cvl, :agent, :lab, :stop] in events
      assert [:medlum_llm, :cvl, :agent, :ontology, :stop] in events
      assert [:medlum_llm, :cvl, :agent, :temporal, :stop] in events
      assert [:medlum_llm, :cvl, :agent, :differential, :stop] in events
    end
  end

  describe "document_events/0" do
    test "returns only document-related events" do
      events = Events.document_events()

      assert is_list(events)
      assert length(events) == 4

      Enum.each(events, fn [prefix, domain | _rest] ->
        assert prefix == :medlum_llm
        assert domain == :document
      end)
    end

    test "includes all expected document events" do
      events = Events.document_events()

      assert [:medlum_llm, :document, :process, :start] in events
      assert [:medlum_llm, :document, :process, :stop] in events
      assert [:medlum_llm, :document, :summarize, :stop] in events
      assert [:medlum_llm, :document, :extract, :stop] in events
    end
  end

  describe "events_by_category/0" do
    test "returns a map with all categories" do
      categories = Events.events_by_category()

      assert is_map(categories)
      assert Map.has_key?(categories, :evaluation)
      assert Map.has_key?(categories, :cvl)
      assert Map.has_key?(categories, :document)
    end

    test "each category contains valid events" do
      categories = Events.events_by_category()

      Enum.each(categories, fn {_category, events} ->
        assert is_list(events)
        refute Enum.empty?(events)

        Enum.each(events, fn event ->
          assert is_list(event)
          assert Enum.all?(event, &is_atom/1)
        end)
      end)
    end
  end

  describe "event_description/1" do
    test "returns description for known evaluation events" do
      desc = Events.event_description([:medlum_llm, :eval, :sample, :stop])

      assert is_binary(desc)
      assert String.contains?(desc, "sample")
    end

    test "returns description for known CVL events" do
      desc = Events.event_description([:medlum_llm, :cvl, :verification, :stop])

      assert is_binary(desc)
      assert String.contains?(desc, "CVL")
    end

    test "returns nil for unknown events" do
      assert Events.event_description([:unknown, :event]) == nil
      assert Events.event_description([:req_llm, :request, :stop]) == nil
    end
  end

  describe "event_category/1" do
    test "returns correct category for evaluation events" do
      assert Events.event_category([:medlum_llm, :eval, :run, :start]) == :evaluation
      assert Events.event_category([:medlum_llm, :eval, :sample, :stop]) == :evaluation
    end

    test "returns correct category for CVL events" do
      assert Events.event_category([:medlum_llm, :cvl, :verification, :stop]) == :cvl
      assert Events.event_category([:medlum_llm, :cvl, :agent, :medication, :stop]) == :cvl
    end

    test "returns correct category for document events" do
      assert Events.event_category([:medlum_llm, :document, :process, :stop]) == :document
      assert Events.event_category([:medlum_llm, :document, :summarize, :stop]) == :document
    end

    test "returns nil for unknown events" do
      assert Events.event_category([:unknown, :event]) == nil
    end
  end

  describe "event_info/1" do
    test "returns info map for known events" do
      info = Events.event_info([:medlum_llm, :eval, :sample, :stop])

      assert is_map(info)
      assert info.category == :evaluation
      assert is_binary(info.description)
    end

    test "returns nil for unknown events" do
      assert Events.event_info([:unknown, :event]) == nil
    end
  end

  describe "medical_event?/1" do
    test "returns true for medical events" do
      assert Events.medical_event?([:medlum_llm, :eval, :sample, :stop])
      assert Events.medical_event?([:medlum_llm, :cvl, :verification, :stop])
      assert Events.medical_event?([:medlum_llm, :document, :process, :stop])
    end

    test "returns false for non-medical events" do
      refute Events.medical_event?([:req_llm, :request, :stop])
      refute Events.medical_event?([:crucible_train, :epoch, :stop])
      refute Events.medical_event?([:unknown, :event])
    end
  end
end
