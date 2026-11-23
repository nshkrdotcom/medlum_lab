defmodule MedlumLlm.Metrics.TelemetryTest do
  use ExUnit.Case, async: false

  alias MedlumLlm.Metrics.Telemetry
  alias MetricsEx.Storage.ETS

  setup do
    ETS.clear()
    # Ensure we start clean
    Telemetry.detach_all()
    :ok
  end

  describe "all_events/0" do
    test "returns complete list of medical events" do
      events = Telemetry.all_events()

      # Check eval events
      assert {[:medlum_llm, :eval, :run, :start], :counter} in events
      assert {[:medlum_llm, :eval, :run, :stop], :histogram} in events
      assert {[:medlum_llm, :eval, :sample, :stop], :histogram} in events
      assert {[:medlum_llm, :eval, :sample, :exception], :counter} in events

      # Check CVL events
      assert {[:medlum_llm, :cvl, :verify, :stop], :histogram} in events
      assert {[:medlum_llm, :cvl, :agent, :verdict], :histogram} in events
      assert {[:medlum_llm, :cvl, :consensus, :complete], :histogram} in events

      # Check inference events
      assert {[:medlum_llm, :chat, :complete], :histogram} in events
      assert {[:medlum_llm, :embed, :complete], :histogram} in events
    end
  end

  describe "eval_events/0" do
    test "returns only evaluation events" do
      events = Telemetry.eval_events()

      assert length(events) == 4

      Enum.each(events, fn {event_name, _type} ->
        assert Enum.take(event_name, 2) == [:medlum_llm, :eval]
      end)
    end
  end

  describe "cvl_events/0" do
    test "returns only CVL events" do
      events = Telemetry.cvl_events()

      assert length(events) == 3

      Enum.each(events, fn {event_name, _type} ->
        assert Enum.take(event_name, 2) == [:medlum_llm, :cvl]
      end)
    end
  end

  describe "inference_events/0" do
    test "returns only inference events" do
      events = Telemetry.inference_events()

      assert length(events) == 2
    end
  end

  describe "attach_all/1" do
    test "attaches handlers for all events by default" do
      :ok = Telemetry.attach_all()

      assert Telemetry.attached?()

      # Cleanup
      Telemetry.detach_all()
    end

    test "attaches with custom handler_id" do
      :ok = Telemetry.attach_all(handler_id: :custom_medical)

      assert Telemetry.attached?(handler_id: :custom_medical)

      # Cleanup
      Telemetry.detach_all(handler_id: :custom_medical)
    end

    test "attaches only specified event categories" do
      :ok = Telemetry.attach_all(events: [:cvl])

      assert Telemetry.attached?()

      # Cleanup
      Telemetry.detach_all()
    end

    test "captures eval telemetry events" do
      :ok = Telemetry.attach_all(events: [:eval])

      # Emit a telemetry event
      :telemetry.execute(
        [:medlum_llm, :eval, :run, :start],
        %{count: 1},
        %{run_id: "test_run"}
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_llm_eval_run_start)
      refute Enum.empty?(results)

      # Cleanup
      Telemetry.detach_all()
    end

    test "captures CVL telemetry events" do
      :ok = Telemetry.attach_all(events: [:cvl])

      # Emit a CVL telemetry event
      :telemetry.execute(
        [:medlum_llm, :cvl, :verify, :stop],
        %{duration: 150},
        %{verdict: :entailment}
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_llm_cvl_verify_stop)
      refute Enum.empty?(results)

      # Cleanup
      Telemetry.detach_all()
    end
  end

  describe "detach_all/1" do
    test "detaches default handler" do
      :ok = Telemetry.attach_all()
      assert Telemetry.attached?()

      result = Telemetry.detach_all()
      assert result == :ok

      refute Telemetry.attached?()
    end

    test "detaches custom handler" do
      :ok = Telemetry.attach_all(handler_id: :my_handler)
      assert Telemetry.attached?(handler_id: :my_handler)

      Telemetry.detach_all(handler_id: :my_handler)
      refute Telemetry.attached?(handler_id: :my_handler)
    end
  end

  describe "attached?/1" do
    test "returns false when not attached" do
      refute Telemetry.attached?()
    end

    test "returns true when attached" do
      :ok = Telemetry.attach_all()
      assert Telemetry.attached?()

      # Cleanup
      Telemetry.detach_all()
    end

    test "checks specific handler_id" do
      :ok = Telemetry.attach_all(handler_id: :specific_handler)

      assert Telemetry.attached?(handler_id: :specific_handler)
      refute Telemetry.attached?(handler_id: :other_handler)

      # Cleanup
      Telemetry.detach_all(handler_id: :specific_handler)
    end
  end
end
