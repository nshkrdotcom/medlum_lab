defmodule MedlumLlm.Datasets.ConfigTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Datasets.Config

  @moduletag :unit

  describe "get/1" do
    test "returns config for known dataset" do
      assert {:ok, config} = Config.get(:medqa)
      assert config.name == "MedQA"
      assert config.repo == "openlifescienceai/medqa"
      assert config.task == :mcq
    end

    test "returns error for unknown dataset" do
      assert {:error, :not_found} = Config.get(:nonexistent)
    end

    test "includes id in returned config" do
      assert {:ok, config} = Config.get(:medqa)
      assert config.id == :medqa
    end
  end

  describe "list/0" do
    test "returns all dataset names" do
      datasets = Config.list()

      assert is_list(datasets)
      assert :medqa in datasets
      assert :pubmedqa in datasets
      assert :reasonmed in datasets
      assert :mmlu_medical in datasets
      assert :n2c2_medication in datasets
      assert :mimic_sum in datasets
    end

    test "returns at least 7 datasets" do
      datasets = Config.list()
      assert length(datasets) >= 7
    end
  end

  describe "all/0" do
    test "returns map of all datasets" do
      all = Config.all()

      assert is_map(all)
      assert Map.has_key?(all, :medqa)
      assert Map.has_key?(all, :pubmedqa)
      assert Map.has_key?(all, :medmcqa)
      assert Map.has_key?(all, :reasonmed)
    end
  end

  describe "by_task/1" do
    test "filters by MCQ task" do
      mcq = Config.by_task(:mcq)

      assert :medqa in mcq
      assert :medmcqa in mcq
      assert :mmlu_medical in mcq
      refute :reasonmed in mcq
      refute :pubmedqa in mcq
    end

    test "filters by reasoning task" do
      reasoning = Config.by_task(:reasoning)

      assert :reasonmed in reasoning
      refute :medqa in reasoning
    end

    test "filters by binary_qa task" do
      binary_qa = Config.by_task(:binary_qa)

      assert :pubmedqa in binary_qa
      refute :medqa in binary_qa
    end

    test "filters by NER task" do
      ner = Config.by_task(:ner)

      assert :n2c2_medication in ner
    end

    test "filters by summarization task" do
      summarization = Config.by_task(:summarization)

      assert :mimic_sum in summarization
    end
  end

  describe "requires_credentials?/1" do
    test "returns true for credentialed datasets" do
      assert Config.requires_credentials?(:n2c2_medication)
      assert Config.requires_credentials?(:mimic_sum)
    end

    test "returns false for public datasets" do
      refute Config.requires_credentials?(:medqa)
      refute Config.requires_credentials?(:pubmedqa)
      refute Config.requires_credentials?(:reasonmed)
    end

    test "returns false for unknown dataset" do
      refute Config.requires_credentials?(:unknown)
    end
  end

  describe "public_datasets/0" do
    test "returns datasets that don't require credentials" do
      public = Config.public_datasets()

      assert is_list(public)
      assert :medqa in public
      assert :pubmedqa in public
      assert :medmcqa in public
      assert :reasonmed in public
      assert :mmlu_medical in public
    end

    test "excludes credentialed datasets" do
      public = Config.public_datasets()

      refute :n2c2_medication in public
      refute :mimic_sum in public
    end
  end

  describe "files_for_split/2" do
    test "returns files for default split" do
      {:ok, files} = Config.files_for_split(:medqa)

      assert is_list(files)
    end

    test "returns empty list for datasets without files defined" do
      {:ok, files} = Config.files_for_split(:reasonmed)

      assert files == []
    end

    test "returns error for unknown dataset" do
      assert {:error, :not_found} = Config.files_for_split(:unknown)
    end
  end

  describe "describe/1" do
    test "returns human-readable description" do
      {:ok, desc} = Config.describe(:medqa)

      assert desc.name == "MedQA"
      assert desc.description == "US Medical Licensing Exam questions"
      assert desc.task == :mcq
      assert is_list(desc.splits)
      assert is_integer(desc.total_samples)
      assert desc.total_samples > 0
      assert is_binary(desc.citation)
    end

    test "returns error for unknown dataset" do
      assert {:error, :not_found} = Config.describe(:unknown)
    end

    test "calculates total_samples from size map" do
      {:ok, desc} = Config.describe(:medqa)

      # MedQA has train: 10178, dev: 1272, test: 1273
      assert desc.total_samples == 10178 + 1272 + 1273
    end
  end

  describe "dataset configurations" do
    test "medqa config has expected fields" do
      {:ok, config} = Config.get(:medqa)

      assert config.default_split == "test"
      assert config.requires_credentials == false
      assert config.streaming == false
      assert is_function(config.preprocessor, 1)
    end

    test "pubmedqa has pqa_labeled config" do
      {:ok, config} = Config.get(:pubmedqa)

      assert config.hf_config == "pqa_labeled"
      assert config.task == :binary_qa
    end

    test "reasonmed has streaming enabled" do
      {:ok, config} = Config.get(:reasonmed)

      assert config.streaming == true
      assert config.task == :reasoning
    end

    test "mmlu_medical has medical_subjects list" do
      {:ok, config} = Config.get(:mmlu_medical)

      assert is_list(config.medical_subjects)
      assert "anatomy" in config.medical_subjects
      assert "clinical_knowledge" in config.medical_subjects
    end

    test "all datasets have required fields" do
      for dataset_id <- Config.list() do
        {:ok, config} = Config.get(dataset_id)

        assert is_binary(config.name), "#{dataset_id} missing name"
        assert is_binary(config.repo), "#{dataset_id} missing repo"
        assert is_function(config.preprocessor, 1), "#{dataset_id} missing preprocessor"
        assert is_binary(config.default_split), "#{dataset_id} missing default_split"
        assert is_list(config.splits), "#{dataset_id} missing splits"
        assert is_atom(config.task), "#{dataset_id} missing task"
        assert is_boolean(config.streaming), "#{dataset_id} missing streaming"
        assert is_boolean(config.requires_credentials), "#{dataset_id} missing requires_credentials"
        assert is_map(config.size), "#{dataset_id} missing size"
        assert is_binary(config.description), "#{dataset_id} missing description"
        assert is_binary(config.citation), "#{dataset_id} missing citation"
      end
    end
  end
end
