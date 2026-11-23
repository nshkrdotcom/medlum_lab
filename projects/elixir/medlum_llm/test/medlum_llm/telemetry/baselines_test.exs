defmodule MedlumLlm.Telemetry.BaselinesTest do
  @moduledoc """
  Tests for the MedlumLlm.Telemetry.Baselines module.
  """
  use ExUnit.Case, async: false

  alias MedlumLlm.Telemetry.Baselines

  setup do
    # Reset baselines to defaults before each test
    Baselines.reset()
    :ok
  end

  describe "list_baselines/1" do
    test "returns baselines for medqa dataset" do
      baselines = Baselines.list_baselines("medqa")

      assert is_list(baselines)
      refute Enum.empty?(baselines)

      # Check structure
      baseline = hd(baselines)
      assert Map.has_key?(baseline, :model)
      assert Map.has_key?(baseline, :dataset)
      assert Map.has_key?(baseline, :accuracy)
      assert Map.has_key?(baseline, :source)
      assert Map.has_key?(baseline, :year)
    end

    test "returns baselines sorted by accuracy descending" do
      baselines = Baselines.list_baselines("medqa")
      accuracies = Enum.map(baselines, & &1.accuracy)

      assert accuracies == Enum.sort(accuracies, :desc)
    end

    test "returns baselines for pubmedqa dataset" do
      baselines = Baselines.list_baselines("pubmedqa")

      assert is_list(baselines)
      refute Enum.empty?(baselines)
    end

    test "returns baselines for medmcqa dataset" do
      baselines = Baselines.list_baselines("medmcqa")

      assert is_list(baselines)
      refute Enum.empty?(baselines)
    end

    test "returns empty list for unknown dataset" do
      baselines = Baselines.list_baselines("unknown_dataset")

      assert baselines == []
    end
  end

  describe "get_baseline/2" do
    test "returns baseline for specific model" do
      {:ok, baseline} = Baselines.get_baseline("medqa", model: "GPT-4")

      assert baseline.model == "GPT-4"
      assert baseline.dataset == "medqa"
      assert baseline.accuracy == 0.861
    end

    test "returns baseline with partial model name match" do
      {:ok, baseline} = Baselines.get_baseline("medqa", model: "gpt")

      assert String.contains?(String.downcase(baseline.model), "gpt")
    end

    test "returns baseline filtered by year" do
      {:ok, baseline} = Baselines.get_baseline("medqa", model: "Med-PaLM", year: 2023)

      assert baseline.year == 2023
      assert String.contains?(baseline.model, "Med-PaLM")
    end

    test "returns error for non-existent model" do
      assert {:error, :not_found} = Baselines.get_baseline("medqa", model: "NonExistentModel")
    end

    test "returns error for non-existent dataset" do
      assert {:error, :not_found} = Baselines.get_baseline("unknown", model: "GPT-4")
    end
  end

  describe "register_baseline/1" do
    test "adds custom baseline" do
      custom = %{
        model: "MyCustomModel",
        dataset: "medqa",
        accuracy: 0.75,
        source: "Internal Testing",
        year: 2026,
        notes: "Custom evaluation"
      }

      assert :ok = Baselines.register_baseline(custom)

      baselines = Baselines.list_baselines("medqa")
      assert Enum.any?(baselines, fn b -> b.model == "MyCustomModel" end)
    end

    test "added baseline is retrievable" do
      custom = %{
        model: "TestModel",
        dataset: "pubmedqa",
        accuracy: 0.82,
        source: "Test",
        year: 2026
      }

      :ok = Baselines.register_baseline(custom)

      {:ok, retrieved} = Baselines.get_baseline("pubmedqa", model: "TestModel")
      assert retrieved.accuracy == 0.82
    end

    test "raises error for missing required keys" do
      incomplete = %{
        model: "Incomplete",
        accuracy: 0.75
      }

      assert_raise ArgumentError, ~r/Missing required baseline keys/, fn ->
        Baselines.register_baseline(incomplete)
      end
    end

    test "raises error for invalid accuracy" do
      invalid = %{
        model: "Invalid",
        dataset: "medqa",
        accuracy: 1.5,
        source: "Test",
        year: 2026
      }

      assert_raise ArgumentError, ~r/accuracy must be between 0 and 1/, fn ->
        Baselines.register_baseline(invalid)
      end
    end

    test "raises error for non-numeric accuracy" do
      invalid = %{
        model: "Invalid",
        dataset: "medqa",
        accuracy: "high",
        source: "Test",
        year: 2026
      }

      assert_raise ArgumentError, ~r/accuracy must be a number/, fn ->
        Baselines.register_baseline(invalid)
      end
    end
  end

  describe "list_datasets/0" do
    test "returns list of available datasets" do
      datasets = Baselines.list_datasets()

      assert is_list(datasets)
      assert "medqa" in datasets
      assert "pubmedqa" in datasets
      assert "medmcqa" in datasets
    end
  end

  describe "reset/0" do
    test "removes custom baselines" do
      custom = %{
        model: "CustomToRemove",
        dataset: "medqa",
        accuracy: 0.70,
        source: "Test",
        year: 2026
      }

      :ok = Baselines.register_baseline(custom)
      assert {:ok, _} = Baselines.get_baseline("medqa", model: "CustomToRemove")

      :ok = Baselines.reset()
      assert {:error, :not_found} = Baselines.get_baseline("medqa", model: "CustomToRemove")
    end

    test "preserves pre-defined baselines after reset" do
      :ok = Baselines.reset()

      {:ok, gpt4} = Baselines.get_baseline("medqa", model: "GPT-4")
      assert gpt4.accuracy == 0.861
    end
  end

  describe "pre-defined baselines" do
    test "medqa includes major models" do
      baselines = Baselines.list_baselines("medqa")
      models = Enum.map(baselines, & &1.model)

      assert "GPT-4" in models
      assert "GPT-3.5" in models
      assert "Med-PaLM 2" in models
    end

    test "all baselines have valid accuracy values" do
      for dataset <- ["medqa", "pubmedqa", "medmcqa"] do
        baselines = Baselines.list_baselines(dataset)

        for baseline <- baselines do
          assert baseline.accuracy >= 0.0
          assert baseline.accuracy <= 1.0
        end
      end
    end

    test "all baselines have required fields" do
      for dataset <- ["medqa", "pubmedqa", "medmcqa"] do
        baselines = Baselines.list_baselines(dataset)

        for baseline <- baselines do
          assert is_binary(baseline.model)
          assert is_binary(baseline.dataset)
          assert is_number(baseline.accuracy)
          assert is_binary(baseline.source)
          assert is_integer(baseline.year)
        end
      end
    end
  end
end
