defmodule MedlumLlm.Eval.BenchmarksTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Eval.Benchmarks

  describe "get/1" do
    test "returns benchmark config for medqa_zero_shot" do
      assert {:ok, config} = Benchmarks.get(:medqa_zero_shot)
      assert config.name == "MedQA Zero-Shot"
      assert config.dataset == :medqa
      assert config.task == :mcq
      assert config.id == :medqa_zero_shot
    end

    test "returns benchmark config for medqa_few_shot" do
      assert {:ok, config} = Benchmarks.get(:medqa_few_shot)
      assert config.name == "MedQA 5-Shot"
      assert config.few_shot.count == 5
    end

    test "returns benchmark config for pubmedqa_zero_shot" do
      assert {:ok, config} = Benchmarks.get(:pubmedqa_zero_shot)
      assert config.task == :binary_qa
    end

    test "returns error for unknown benchmark" do
      assert {:error, :not_found} = Benchmarks.get(:nonexistent)
    end
  end

  describe "get!/1" do
    test "returns config for valid benchmark" do
      config = Benchmarks.get!(:medqa_zero_shot)
      assert config.name == "MedQA Zero-Shot"
    end

    test "raises for unknown benchmark" do
      assert_raise ArgumentError, ~r/Unknown benchmark/, fn ->
        Benchmarks.get!(:nonexistent)
      end
    end
  end

  describe "list/0" do
    test "returns all benchmark names" do
      benchmarks = Benchmarks.list()
      assert is_list(benchmarks)
      assert :medqa_zero_shot in benchmarks
      assert :pubmedqa_zero_shot in benchmarks
      assert :cvl_hallucination in benchmarks
    end

    test "includes at least 7 benchmarks" do
      benchmarks = Benchmarks.list()
      assert length(benchmarks) >= 7
    end
  end

  describe "by_task/1" do
    test "filters by MCQ task" do
      mcq_benchmarks = Benchmarks.by_task(:mcq)
      assert :medqa_zero_shot in mcq_benchmarks
      assert :medqa_few_shot in mcq_benchmarks
      assert :medmcqa_zero_shot in mcq_benchmarks
      assert :mmlu_medical_zero_shot in mcq_benchmarks
      refute :cvl_hallucination in mcq_benchmarks
    end

    test "filters by binary_qa task" do
      binary_benchmarks = Benchmarks.by_task(:binary_qa)
      assert :pubmedqa_zero_shot in binary_benchmarks
      refute :medqa_zero_shot in binary_benchmarks
    end

    test "filters by mcq_cot task" do
      cot_benchmarks = Benchmarks.by_task(:mcq_cot)
      assert :medqa_cot in cot_benchmarks
    end

    test "filters by cvl_verification task" do
      cvl_benchmarks = Benchmarks.by_task(:cvl_verification)
      assert :cvl_hallucination in cvl_benchmarks
    end
  end

  describe "by_dataset/1" do
    test "filters by medqa dataset" do
      medqa_benchmarks = Benchmarks.by_dataset(:medqa)
      assert :medqa_zero_shot in medqa_benchmarks
      assert :medqa_few_shot in medqa_benchmarks
      assert :medqa_cot in medqa_benchmarks
      assert :cvl_hallucination in medqa_benchmarks
      refute :pubmedqa_zero_shot in medqa_benchmarks
    end

    test "filters by pubmedqa dataset" do
      pubmedqa_benchmarks = Benchmarks.by_dataset(:pubmedqa)
      assert :pubmedqa_zero_shot in pubmedqa_benchmarks
    end
  end

  describe "default_models/1" do
    test "returns models for medqa_zero_shot" do
      models = Benchmarks.default_models(:medqa_zero_shot)
      assert :biomistral_7b in models
      assert :openbio_8b in models
    end

    test "returns empty list for unknown benchmark" do
      assert Benchmarks.default_models(:nonexistent) == []
    end
  end

  describe "all/0" do
    test "returns all benchmarks as a map" do
      all = Benchmarks.all()
      assert is_map(all)
      assert Map.has_key?(all, :medqa_zero_shot)
      assert all.medqa_zero_shot.name == "MedQA Zero-Shot"
    end
  end

  describe "with_metric/1" do
    test "filters by accuracy metric" do
      with_accuracy = Benchmarks.with_metric(:accuracy)
      assert :medqa_zero_shot in with_accuracy
      assert :medqa_few_shot in with_accuracy
    end

    test "filters by hallucination_recall metric" do
      with_hall_recall = Benchmarks.with_metric(:hallucination_recall)
      assert :cvl_hallucination in with_hall_recall
      refute :medqa_zero_shot in with_hall_recall
    end
  end

  describe "prompt_template/1" do
    test "returns template for medqa_zero_shot" do
      assert Benchmarks.prompt_template(:medqa_zero_shot) == :zero_shot_mcq
    end

    test "returns template for medqa_cot" do
      assert Benchmarks.prompt_template(:medqa_cot) == :chain_of_thought_mcq
    end

    test "returns nil for unknown benchmark" do
      assert Benchmarks.prompt_template(:nonexistent) == nil
    end
  end

  describe "streaming?/1" do
    test "returns true for reasonmed_sample" do
      assert Benchmarks.streaming?(:reasonmed_sample)
    end

    test "returns false for medqa_zero_shot" do
      refute Benchmarks.streaming?(:medqa_zero_shot)
    end
  end

  describe "timeout_ms/1" do
    test "returns timeout for benchmark" do
      assert Benchmarks.timeout_ms(:medqa_zero_shot) == 60_000
      assert Benchmarks.timeout_ms(:medqa_cot) == 120_000
      assert Benchmarks.timeout_ms(:reasonmed_sample) == 180_000
    end

    test "returns nil for unknown benchmark" do
      assert Benchmarks.timeout_ms(:nonexistent) == nil
    end
  end
end
