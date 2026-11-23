defmodule MedlumLlm.Telemetry.MetricsTest do
  @moduledoc """
  Tests for the MedlumLlm.Telemetry.Metrics module.
  """
  use ExUnit.Case

  alias MedlumLlm.Telemetry.Metrics
  alias CrucibleTelemetry.{Experiment, Store}

  setup do
    # Start a test experiment
    {:ok, experiment} =
      Experiment.start(
        name: "medical_metrics_test_#{System.unique_integer([:positive])}",
        hypothesis: "Test medical metrics calculation"
      )

    on_exit(fn ->
      Experiment.cleanup(experiment.id)
    end)

    {:ok, experiment: experiment}
  end

  describe "calculate_cvl_metrics/1" do
    test "returns error when no CVL events", %{experiment: experiment} do
      assert {:error, :no_data} = Metrics.calculate_cvl_metrics(experiment.id)
    end

    test "calculates metrics from CVL verification events", %{experiment: experiment} do
      # Insert sample CVL events
      events = [
        create_cvl_event(experiment, :entailment, false, 100.0),
        create_cvl_event(experiment, :entailment, false, 120.0),
        create_cvl_event(experiment, :contradiction, true, 150.0),
        create_cvl_event(experiment, :neutral, true, 180.0),
        create_cvl_event(experiment, :entailment, false, 90.0)
      ]

      for event <- events do
        Store.insert(experiment.id, event)
      end

      {:ok, metrics} = Metrics.calculate_cvl_metrics(experiment.id)

      assert metrics.total_verifications == 5
      assert metrics.entailment_count == 3
      assert metrics.contradiction_count == 1
      assert metrics.neutral_count == 1

      # Mean latency
      assert_in_delta metrics.mean_verification_latency_ms, 128.0, 0.1
    end

    test "calculates hallucination precision and recall", %{experiment: experiment} do
      # Insert events with known hallucination detection results
      events = [
        # True positive: detected hallucination in contradiction
        create_cvl_event(experiment, :contradiction, true, 100.0),
        # True positive: detected hallucination in neutral
        create_cvl_event(experiment, :neutral, true, 100.0),
        # False positive: detected hallucination but was entailment
        create_cvl_event(experiment, :entailment, true, 100.0),
        # True negative: no detection for entailment
        create_cvl_event(experiment, :entailment, false, 100.0),
        # False negative: missed hallucination in contradiction
        create_cvl_event(experiment, :contradiction, false, 100.0)
      ]

      for event <- events do
        Store.insert(experiment.id, event)
      end

      {:ok, metrics} = Metrics.calculate_cvl_metrics(experiment.id)

      # Precision = TP / (TP + FP) = 2 / (2 + 1) = 0.667
      assert_in_delta metrics.hallucination_precision, 0.667, 0.01

      # Recall = TP / (TP + FN) = 2 / (2 + 1) = 0.667
      assert_in_delta metrics.hallucination_recall, 0.667, 0.01

      # F1 = 2 * P * R / (P + R) = 2 * 0.667 * 0.667 / (0.667 + 0.667) = 0.667
      assert_in_delta metrics.hallucination_f1, 0.667, 0.01
    end

    test "calculates agent agreement rate", %{experiment: experiment} do
      # Insert events with varying disagreement counts
      events = [
        create_cvl_event(experiment, :entailment, false, 100.0, 0),
        create_cvl_event(experiment, :entailment, false, 100.0, 0),
        create_cvl_event(experiment, :contradiction, true, 100.0, 2),
        create_cvl_event(experiment, :neutral, true, 100.0, 1)
      ]

      for event <- events do
        Store.insert(experiment.id, event)
      end

      {:ok, metrics} = Metrics.calculate_cvl_metrics(experiment.id)

      # 2 out of 4 have zero disagreements
      assert metrics.agent_agreement_rate == 0.5
    end
  end

  describe "calculate_model_metrics/1" do
    test "returns error when no sample events", %{experiment: experiment} do
      assert {:error, :no_data} = Metrics.calculate_model_metrics(experiment.id)
    end

    test "calculates metrics per model", %{experiment: experiment} do
      # Insert sample evaluation events for multiple models
      events = [
        create_sample_event(experiment, :biomistral_7b, true, 1200.0, 25.0),
        create_sample_event(experiment, :biomistral_7b, true, 1100.0, 27.0),
        create_sample_event(experiment, :biomistral_7b, false, 1300.0, 23.0),
        create_sample_event(experiment, :openbio_8b, true, 800.0, 35.0),
        create_sample_event(experiment, :openbio_8b, true, 850.0, 33.0)
      ]

      for event <- events do
        Store.insert(experiment.id, event)
      end

      {:ok, metrics} = Metrics.calculate_model_metrics(experiment.id)

      # Check biomistral metrics
      assert Map.has_key?(metrics, :biomistral_7b)
      biomistral = metrics[:biomistral_7b]
      assert biomistral.model == :biomistral_7b
      assert biomistral.total_samples == 3
      assert biomistral.correct == 2
      assert_in_delta biomistral.accuracy, 0.667, 0.01

      # Check openbio metrics
      assert Map.has_key?(metrics, :openbio_8b)
      openbio = metrics[:openbio_8b]
      assert openbio.model == :openbio_8b
      assert openbio.total_samples == 2
      assert openbio.correct == 2
      assert openbio.accuracy == 1.0
    end

    test "calculates latency percentiles", %{experiment: experiment} do
      # Insert events with varying latencies
      latencies = [100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0, 1000.0]

      events =
        Enum.map(latencies, fn latency ->
          create_sample_event(experiment, :test_model, true, latency, 25.0)
        end)

      for event <- events do
        Store.insert(experiment.id, event)
      end

      {:ok, metrics} = Metrics.calculate_model_metrics(experiment.id)

      test_model = metrics[:test_model]
      assert test_model.latency_p50 != nil
      assert test_model.latency_p95 != nil

      # P50 should be around 500-600
      assert test_model.latency_p50 >= 500.0
      assert test_model.latency_p50 <= 600.0

      # P95 should be around 950
      assert test_model.latency_p95 >= 900.0
    end

    test "calculates tokens per second", %{experiment: experiment} do
      events = [
        create_sample_event(experiment, :test_model, true, 100.0, 20.0),
        create_sample_event(experiment, :test_model, true, 100.0, 30.0),
        create_sample_event(experiment, :test_model, true, 100.0, 25.0)
      ]

      for event <- events do
        Store.insert(experiment.id, event)
      end

      {:ok, metrics} = Metrics.calculate_model_metrics(experiment.id)

      test_model = metrics[:test_model]
      assert test_model.tokens_per_second != nil
      assert_in_delta test_model.tokens_per_second, 25.0, 0.01
    end

    test "counts errors from exception events", %{experiment: experiment} do
      events = [
        create_sample_event(experiment, :test_model, true, 100.0, 25.0),
        create_sample_event(experiment, :test_model, true, 100.0, 25.0),
        create_exception_event(experiment, :test_model),
        create_exception_event(experiment, :test_model)
      ]

      for event <- events do
        Store.insert(experiment.id, event)
      end

      {:ok, metrics} = Metrics.calculate_model_metrics(experiment.id)

      test_model = metrics[:test_model]
      assert test_model.total_samples == 2
      assert test_model.errors == 2
    end
  end

  # Helper functions to create test events

  defp create_cvl_event(experiment, verdict, hallucination_detected, latency_ms, disagreement_count \\ 0) do
    %{
      event_id: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
      event_name: [:medlum_llm, :cvl, :verification, :stop],
      timestamp: System.system_time(:microsecond),
      experiment_id: experiment.id,
      experiment_name: experiment.name,
      condition: experiment.condition,
      tags: experiment.tags,
      measurements: %{duration: round(latency_ms * 1_000_000), agent_calls: 5},
      metadata: %{
        verification_id: "cvl_#{System.unique_integer([:positive])}",
        verdict: verdict,
        confidence: 0.9,
        hallucination_detected: hallucination_detected,
        disagreement_count: disagreement_count
      },
      latency_ms: latency_ms,
      cost_usd: nil,
      success: true
    }
  end

  defp create_sample_event(experiment, model, correct, latency_ms, tps) do
    %{
      event_id: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
      event_name: [:medlum_llm, :eval, :sample, :stop],
      timestamp: System.system_time(:microsecond),
      experiment_id: experiment.id,
      experiment_name: experiment.name,
      condition: experiment.condition,
      tags: experiment.tags,
      measurements: %{
        duration: round(latency_ms * 1_000_000),
        input_tokens: 150,
        output_tokens: 25,
        tokens_per_second: tps
      },
      metadata: %{
        run_id: "run_#{System.unique_integer([:positive])}",
        model: model,
        sample_idx: System.unique_integer([:positive]),
        predicted: if(correct, do: "A", else: "B"),
        correct_answer: "A",
        correct: correct
      },
      latency_ms: latency_ms,
      cost_usd: 0.001,
      success: true
    }
  end

  defp create_exception_event(experiment, model) do
    %{
      event_id: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
      event_name: [:medlum_llm, :eval, :sample, :exception],
      timestamp: System.system_time(:microsecond),
      experiment_id: experiment.id,
      experiment_name: experiment.name,
      condition: experiment.condition,
      tags: experiment.tags,
      measurements: %{duration: 60_000_000_000},
      metadata: %{
        run_id: "run_#{System.unique_integer([:positive])}",
        model: model,
        sample_idx: System.unique_integer([:positive]),
        error: :timeout,
        message: "Timeout"
      },
      latency_ms: 60_000.0,
      cost_usd: nil,
      success: false
    }
  end
end
