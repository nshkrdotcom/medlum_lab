defmodule MedlumLlm.DatasetsTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Datasets

  @moduletag :unit

  describe "available/0" do
    test "returns list of dataset names" do
      datasets = Datasets.available()

      assert is_list(datasets)
      assert :medqa in datasets
      assert :pubmedqa in datasets
      assert :reasonmed in datasets
    end
  end

  describe "info/1" do
    test "returns dataset information" do
      {:ok, info} = Datasets.info(:medqa)

      assert info.name == "MedQA"
      assert info.task == :mcq
      assert is_binary(info.repo)
    end

    test "returns error for unknown dataset" do
      assert {:error, :not_found} = Datasets.info(:unknown)
    end
  end

  describe "describe/1" do
    test "returns human-readable description" do
      {:ok, desc} = Datasets.describe(:medqa)

      assert desc.name == "MedQA"
      assert is_integer(desc.total_samples)
      assert desc.total_samples > 0
    end

    test "returns error for unknown dataset" do
      assert {:error, :not_found} = Datasets.describe(:unknown)
    end
  end

  describe "by_task/1" do
    test "filters datasets by task type" do
      mcq = Datasets.by_task(:mcq)

      assert :medqa in mcq
      assert :medmcqa in mcq
      refute :pubmedqa in mcq
    end
  end

  describe "requires_credentials?/1" do
    test "returns true for credentialed datasets" do
      assert Datasets.requires_credentials?(:n2c2_medication)
    end

    test "returns false for public datasets" do
      refute Datasets.requires_credentials?(:medqa)
    end
  end

  # NOTE: Integration tests for load/2 and load_all_splits/2 would require
  # mocking HfDatasetsEx or running against real HuggingFace Hub.
  # These tests are placed in a separate integration test file.

  describe "load/2 error handling" do
    test "returns error for unknown dataset" do
      assert {:error, :not_found} = Datasets.load(:unknown_dataset)
    end
  end
end
