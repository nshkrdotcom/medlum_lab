defmodule MedlumLlm.Metrics.EvaluationTest do
  use ExUnit.Case, async: false

  alias MedlumLlm.Metrics.Evaluation
  alias MetricsEx.Storage.ETS

  setup do
    ETS.clear()
    :ok
  end

  describe "error_types/0" do
    test "returns recognized error types" do
      types = Evaluation.error_types()

      assert :timeout in types
      assert :provider_error in types
      assert :parse_error in types
      assert :validation_error in types
      assert :network_error in types
      assert :oom_error in types
      assert :unknown in types
    end
  end

  describe "record_accuracy/2" do
    test "records accuracy gauge with required tags" do
      Evaluation.record_accuracy(0.75,
        model: "biomistral_7b",
        dataset: "medqa",
        benchmark: "zero_shot"
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_eval_accuracy)
      assert length(results) == 1

      metric = hd(results)
      assert metric.value == 0.75
      assert metric.type == :gauge
      assert metric.tags.model == "biomistral_7b"
      assert metric.tags.dataset == "medqa"
      assert metric.tags.benchmark == "zero_shot"
    end

    test "uses default benchmark when not provided" do
      Evaluation.record_accuracy(0.68,
        model: "openbiollm_8b",
        dataset: "pubmedqa"
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_eval_accuracy)
      metric = hd(results)
      assert metric.tags.benchmark == "default"
    end

    test "includes run_id in tags when provided" do
      Evaluation.record_accuracy(0.72,
        model: "meditron_7b",
        dataset: "medmcqa",
        run_id: "run_456"
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_eval_accuracy)
      metric = hd(results)
      assert metric.tags.run_id == "run_456"
    end

    test "handles atom model names" do
      Evaluation.record_accuracy(0.65,
        model: :biomistral_7b,
        dataset: :medqa
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_eval_accuracy)
      assert length(results) == 1
    end
  end

  describe "record_accuracy_with_ci/4" do
    test "records accuracy and CI bounds" do
      Evaluation.record_accuracy_with_ci(0.75, 0.68, 0.81,
        model: "biomistral_7b",
        dataset: "medqa"
      )

      Process.sleep(50)

      # Check accuracy
      accuracy_results = ETS.query(name: :medlum_eval_accuracy)
      assert length(accuracy_results) == 1
      assert hd(accuracy_results).value == 0.75

      # Check CI lower
      ci_lower_results = ETS.query(name: :medlum_eval_accuracy_ci_lower)
      assert length(ci_lower_results) == 1
      assert hd(ci_lower_results).value == 0.68

      # Check CI upper
      ci_upper_results = ETS.query(name: :medlum_eval_accuracy_ci_upper)
      assert length(ci_upper_results) == 1
      assert hd(ci_upper_results).value == 0.81
    end

    test "CI bounds have matching tags" do
      Evaluation.record_accuracy_with_ci(0.70, 0.62, 0.77,
        model: "test_model",
        dataset: "test_dataset",
        benchmark: "test_bench"
      )

      Process.sleep(50)

      ci_lower = hd(ETS.query(name: :medlum_eval_accuracy_ci_lower))
      ci_upper = hd(ETS.query(name: :medlum_eval_accuracy_ci_upper))

      assert ci_lower.tags.model == "test_model"
      assert ci_lower.tags.dataset == "test_dataset"
      assert ci_lower.tags.benchmark == "test_bench"

      assert ci_upper.tags.model == "test_model"
      assert ci_upper.tags.dataset == "test_dataset"
      assert ci_upper.tags.benchmark == "test_bench"
    end
  end

  describe "record_latency/2" do
    test "records latency histogram" do
      Evaluation.record_latency(1523.5,
        model: "biomistral_7b",
        benchmark: "zero_shot"
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_eval_inference_latency_ms)
      assert length(results) == 1

      metric = hd(results)
      assert metric.value == 1523.5
      assert metric.type == :histogram
      assert metric.tags.model == "biomistral_7b"
      assert metric.tags.benchmark == "zero_shot"
    end

    test "includes provider when specified" do
      Evaluation.record_latency(800.0,
        model: "test_model",
        benchmark: "default",
        provider: :ollama
      )

      Process.sleep(50)

      metric = hd(ETS.query(name: :medlum_eval_inference_latency_ms))
      assert metric.tags.provider == :ollama
    end
  end

  describe "record_error/2" do
    test "records error count with type" do
      Evaluation.record_error(:timeout,
        model: "biomistral_7b",
        benchmark: "zero_shot"
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_eval_error_count)
      assert length(results) == 1

      metric = hd(results)
      assert metric.type == :counter
      assert metric.tags.error_type == :timeout
      assert metric.tags.model == "biomistral_7b"
    end

    test "uses default values when not provided" do
      Evaluation.record_error(:provider_error)
      Process.sleep(50)

      metric = hd(ETS.query(name: :medlum_eval_error_count))
      assert metric.tags.model == "unknown"
      assert metric.tags.benchmark == "default"
    end
  end

  describe "record_sample_complete/1" do
    test "records sample completion with latency" do
      Evaluation.record_sample_complete(%{
        latency_ms: 1234.5,
        model: "biomistral_7b",
        benchmark: "zero_shot"
      })

      Process.sleep(50)

      results = ETS.query(name: :medlum_eval_inference_latency_ms)
      assert length(results) == 1
      assert hd(results).value == 1234.5
    end
  end

  describe "record_sample_failed/2" do
    test "records failure and classifies error" do
      Evaluation.record_sample_failed(
        %{model: "test_model", benchmark: "test"},
        {:timeout, 30_000}
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_eval_error_count)
      assert length(results) == 1
      assert hd(results).tags.error_type == :timeout
    end
  end

  describe "classify_error/1" do
    test "classifies timeout errors" do
      assert Evaluation.classify_error({:timeout, 30_000}) == :timeout
      assert Evaluation.classify_error({:error, :timeout}) == :timeout
      assert Evaluation.classify_error(:timeout) == :timeout
    end

    test "classifies network errors" do
      assert Evaluation.classify_error({:error, :econnrefused}) == :network_error
      assert Evaluation.classify_error({:error, :nxdomain}) == :network_error
      assert Evaluation.classify_error({:error, :ehostunreach}) == :network_error
    end

    test "classifies provider errors" do
      assert Evaluation.classify_error({:error, {:http_error, 500}}) == :provider_error
    end

    test "classifies parse errors" do
      assert Evaluation.classify_error({:error, :parse_error}) == :parse_error
    end

    test "classifies validation errors" do
      assert Evaluation.classify_error({:error, :validation_error}) == :validation_error
    end

    test "returns unknown for unrecognized errors" do
      assert Evaluation.classify_error({:error, :something_else}) == :unknown
      assert Evaluation.classify_error("random error") == :unknown
    end
  end
end
