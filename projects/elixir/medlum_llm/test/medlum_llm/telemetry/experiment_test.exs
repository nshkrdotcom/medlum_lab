defmodule MedlumLlm.Telemetry.ExperimentTest do
  @moduledoc """
  Tests for the MedlumLlm.Telemetry.Experiment module.
  """
  use ExUnit.Case

  alias MedlumLlm.Telemetry.Experiment
  alias CrucibleTelemetry.Experiment, as: BaseExperiment

  setup do
    on_exit(fn ->
      # Clean up any experiments created during tests
      BaseExperiment.list()
      |> Enum.filter(fn exp -> String.starts_with?(exp.name, "medical_exp_test") end)
      |> Enum.each(fn exp -> BaseExperiment.cleanup(exp.id) end)
    end)

    :ok
  end

  describe "start_evaluation/2" do
    test "creates experiment with basic options" do
      {:ok, exp} =
        Experiment.start_evaluation("medical_exp_test_#{System.unique_integer([:positive])}",
          benchmark: :medqa_zero_shot,
          models: [:biomistral_7b]
        )

      assert exp.status == :running
      assert exp.condition == "evaluation"
      assert "evaluation" in exp.tags
      assert "medqa_zero_shot" in exp.tags
      assert "biomistral_7b" in exp.tags
    end

    test "includes hypothesis in experiment" do
      {:ok, exp} =
        Experiment.start_evaluation("medical_exp_test_#{System.unique_integer([:positive])}",
          benchmark: :medqa,
          models: [:test_model],
          hypothesis: "Model achieves >70% accuracy"
        )

      assert exp.hypothesis == "Model achieves >70% accuracy"
    end

    test "stores metadata with benchmark and models" do
      {:ok, exp} =
        Experiment.start_evaluation("medical_exp_test_#{System.unique_integer([:positive])}",
          benchmark: :pubmedqa_labeled,
          models: [:biomistral_7b, :openbio_8b],
          seed: 123,
          concurrency: 4
        )

      assert exp.metadata.benchmark == :pubmedqa_labeled
      assert exp.metadata.models == [:biomistral_7b, :openbio_8b]
      assert exp.metadata.seed == 123
      assert exp.metadata.concurrency == 4
    end

    test "stores grant context when provided" do
      {:ok, exp} =
        Experiment.start_evaluation("medical_exp_test_#{System.unique_integer([:positive])}",
          benchmark: :medqa,
          models: [:test_model],
          grant: %{program: "Clinical AI Benchmark", milestone: "Q2"}
        )

      assert exp.metadata.grant == %{program: "Clinical AI Benchmark", milestone: "Q2"}
    end

    test "uses default seed when not provided" do
      {:ok, exp} =
        Experiment.start_evaluation("medical_exp_test_#{System.unique_integer([:positive])}",
          benchmark: :medqa,
          models: [:test_model]
        )

      assert exp.metadata.seed == 42
    end

    test "respects custom condition" do
      {:ok, exp} =
        Experiment.start_evaluation("medical_exp_test_#{System.unique_integer([:positive])}",
          benchmark: :medqa,
          models: [:test_model],
          condition: "treatment"
        )

      assert exp.condition == "treatment"
    end

    test "merges custom tags with auto-generated tags" do
      {:ok, exp} =
        Experiment.start_evaluation("medical_exp_test_#{System.unique_integer([:positive])}",
          benchmark: :medqa,
          models: [:biomistral_7b],
          tags: ["q4_k_m", "zero-shot"]
        )

      assert "evaluation" in exp.tags
      assert "medqa" in exp.tags
      assert "biomistral_7b" in exp.tags
      assert "q4_k_m" in exp.tags
      assert "zero-shot" in exp.tags
    end

    test "stores pre-captured environment when provided" do
      env = %{elixir_version: "1.17.0", otp_version: "27.0"}

      {:ok, exp} =
        Experiment.start_evaluation("medical_exp_test_#{System.unique_integer([:positive])}",
          benchmark: :medqa,
          models: [:test_model],
          environment: env
        )

      assert exp.metadata.environment == env
    end
  end

  describe "with_environment/1" do
    test "adds environment to experiment" do
      {:ok, base_exp} = BaseExperiment.start(name: "medical_exp_test_#{System.unique_integer([:positive])}")

      updated = Experiment.with_environment(base_exp)

      assert Map.has_key?(updated.metadata, :environment)

      # Environment will be populated if CrucibleBench is available, nil otherwise
      if Code.ensure_loaded?(CrucibleBench.Environment) do
        assert is_map(updated.metadata.environment)
      else
        assert updated.metadata.environment == nil
      end
    end
  end

  describe "evaluation_metadata/1" do
    test "builds metadata with all provided options" do
      metadata =
        Experiment.evaluation_metadata(
          benchmark: :medqa_zero_shot,
          models: [:biomistral_7b],
          seed: 123,
          concurrency: 4,
          retention: :errors_only
        )

      assert metadata.benchmark == :medqa_zero_shot
      assert metadata.models == [:biomistral_7b]
      assert metadata.seed == 123
      assert metadata.concurrency == 4
      assert metadata.retention == :errors_only
    end

    test "uses defaults for missing options" do
      metadata = Experiment.evaluation_metadata([])

      assert metadata.seed == 42
      assert metadata.concurrency == 1
      assert metadata.retention == :full
      assert metadata.models == []
    end

    test "omits nil values from metadata" do
      metadata =
        Experiment.evaluation_metadata(
          benchmark: :medqa,
          models: [:test_model]
        )

      refute Map.has_key?(metadata, :dataset)
      refute Map.has_key?(metadata, :grant)
    end

    test "includes dataset when provided" do
      metadata =
        Experiment.evaluation_metadata(
          benchmark: :medqa,
          models: [:test_model],
          dataset: %{name: "medqa", split: "test", revision: "abc123"}
        )

      assert metadata.dataset == %{name: "medqa", split: "test", revision: "abc123"}
    end
  end
end
