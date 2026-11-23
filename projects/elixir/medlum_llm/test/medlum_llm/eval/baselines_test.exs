defmodule MedlumLlm.Eval.BaselinesTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Eval.Baselines

  describe "get/1 (dataset only)" do
    test "returns baselines for medqa" do
      baselines = Baselines.get(:medqa)
      assert is_map(baselines)
      assert Map.has_key?(baselines, :gpt4)
      assert Map.has_key?(baselines, :biomistral_7b)
    end

    test "returns empty map for unknown dataset" do
      assert Baselines.get(:unknown) == %{}
    end
  end

  describe "get/2 (dataset and model)" do
    test "returns baseline for gpt4 on medqa" do
      assert {:ok, baseline} = Baselines.get(:medqa, :gpt4)
      assert baseline.accuracy == 0.86
      assert baseline.source =~ "GPT-4"
    end

    test "returns baseline for biomistral_7b on medqa" do
      assert {:ok, baseline} = Baselines.get(:medqa, :biomistral_7b)
      assert baseline.accuracy == 0.61
      assert baseline.source =~ "BioMistral"
    end

    test "returns baseline for ii_medical_8b on medqa" do
      assert {:ok, baseline} = Baselines.get(:medqa, :ii_medical_8b)
      assert baseline.accuracy == 0.88
    end

    test "returns error for unknown model" do
      assert {:error, :not_found} = Baselines.get(:medqa, :nonexistent)
    end

    test "returns error for unknown dataset" do
      assert {:error, :not_found} = Baselines.get(:nonexistent, :gpt4)
    end
  end

  describe "compare/3" do
    test "returns :match when within 5% of baseline" do
      # biomistral_7b baseline is 0.61
      assert :match = Baselines.compare(:medqa, :biomistral_7b, 0.63)
      assert :match = Baselines.compare(:medqa, :biomistral_7b, 0.58)
      assert :match = Baselines.compare(:medqa, :biomistral_7b, 0.61)
    end

    test "returns :above when more than 5% above baseline" do
      # biomistral_7b baseline is 0.61
      assert :above = Baselines.compare(:medqa, :biomistral_7b, 0.70)
      assert :above = Baselines.compare(:medqa, :biomistral_7b, 0.80)
    end

    test "returns :below when more than 5% below baseline" do
      # biomistral_7b baseline is 0.61
      assert :below = Baselines.compare(:medqa, :biomistral_7b, 0.50)
      assert :below = Baselines.compare(:medqa, :biomistral_7b, 0.40)
    end

    test "returns :no_baseline for unknown model" do
      assert :no_baseline = Baselines.compare(:medqa, :unknown_model, 0.70)
    end

    test "returns :no_baseline for unknown dataset" do
      assert :no_baseline = Baselines.compare(:unknown_dataset, :gpt4, 0.70)
    end
  end

  describe "compare/4 with custom tolerance" do
    test "uses custom tolerance" do
      # biomistral_7b baseline is 0.61, result is 0.64 (diff = 0.03)
      assert :match = Baselines.compare(:medqa, :biomistral_7b, 0.64, tolerance: 0.05)
      assert :above = Baselines.compare(:medqa, :biomistral_7b, 0.64, tolerance: 0.02)
    end
  end

  describe "format_comparison/3" do
    test "formats comparison with positive difference" do
      result = Baselines.format_comparison(:medqa, :biomistral_7b, 0.65)
      assert result =~ "65.0%"
      assert result =~ "+4.0%"
      assert result =~ "baseline 61.0%"
    end

    test "formats comparison with negative difference" do
      result = Baselines.format_comparison(:medqa, :biomistral_7b, 0.55)
      assert result =~ "55.0%"
      assert result =~ "-6.0%"
      assert result =~ "baseline 61.0%"
    end

    test "handles no baseline" do
      result = Baselines.format_comparison(:medqa, :unknown_model, 0.70)
      assert result =~ "70.0%"
      assert result =~ "no baseline"
    end
  end

  describe "datasets/0" do
    test "returns all datasets with baselines" do
      datasets = Baselines.datasets()
      assert :medqa in datasets
      assert :pubmedqa in datasets
      assert :medmcqa in datasets
      assert :mmlu_medical in datasets
    end
  end

  describe "models/1" do
    test "returns models for medqa" do
      models = Baselines.models(:medqa)
      assert :gpt4 in models
      assert :biomistral_7b in models
      assert :openbio_8b in models
    end

    test "returns empty list for unknown dataset" do
      assert Baselines.models(:unknown) == []
    end
  end

  describe "all/0" do
    test "returns nested map of all baselines" do
      all = Baselines.all()
      assert is_map(all)
      assert all.medqa.gpt4.accuracy == 0.86
    end
  end

  describe "exists?/2" do
    test "returns true for existing baseline" do
      assert Baselines.exists?(:medqa, :gpt4)
      assert Baselines.exists?(:medqa, :biomistral_7b)
    end

    test "returns false for non-existing baseline" do
      refute Baselines.exists?(:medqa, :unknown)
      refute Baselines.exists?(:unknown, :gpt4)
    end
  end

  describe "accuracy/2" do
    test "returns accuracy for existing baseline" do
      assert Baselines.accuracy(:medqa, :gpt4) == 0.86
      assert Baselines.accuracy(:medqa, :biomistral_7b) == 0.61
    end

    test "returns nil for non-existing baseline" do
      assert Baselines.accuracy(:medqa, :unknown) == nil
    end
  end

  describe "summary_table/1" do
    test "returns sorted list of baseline info" do
      table = Baselines.summary_table(:medqa)
      assert is_list(table)
      assert length(table) > 0

      # Check first item has expected fields
      first = List.first(table)
      assert Map.has_key?(first, :model)
      assert Map.has_key?(first, :accuracy)
      assert Map.has_key?(first, :accuracy_pct)
      assert Map.has_key?(first, :source)

      # Check sorted by accuracy descending
      accuracies = Enum.map(table, & &1.accuracy)
      assert accuracies == Enum.sort(accuracies, :desc)
    end
  end
end
