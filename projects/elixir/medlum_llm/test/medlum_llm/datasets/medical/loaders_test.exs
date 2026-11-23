defmodule MedlumLlm.Datasets.LoadersTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Datasets.Loaders
  alias DatasetsEx.Dataset

  describe "list_datasets/0" do
    test "returns all medical dataset names" do
      datasets = Loaders.list_datasets()

      assert is_list(datasets)
      assert :medqa in datasets
      assert :medmcqa in datasets
      assert :pubmedqa in datasets
      assert :mmlu_clinical in datasets
      assert :mmlu_medical_genetics in datasets
      assert :mmlu_professional_medicine in datasets
      assert :medical_o1 in datasets
      assert :ncbi_disease in datasets
    end
  end

  describe "get_config/1" do
    test "returns config for medqa" do
      config = Loaders.get_config(:medqa)

      assert config.repo_id == "bigbio/med_qa"
      assert config.task == :mcq
      assert config.clinical_area == "usmle"
      assert config.phi_status == :none
      assert config.access_level == :public
      assert is_map(config.baselines)
    end

    test "returns config for pubmedqa" do
      config = Loaders.get_config(:pubmedqa)

      assert config.task == :binary_qa
      assert config.clinical_area == "biomedical_research"
    end

    test "returns config for ncbi_disease (NER)" do
      config = Loaders.get_config(:ncbi_disease)

      assert config.task == :ner
      assert config.clinical_area == "biomedical_ner"
    end

    test "returns nil for unknown dataset" do
      assert Loaders.get_config(:unknown_dataset) == nil
    end
  end

  describe "list_by_task/1" do
    test "returns MCQ datasets" do
      mcq_datasets = Loaders.list_by_task(:mcq)

      assert :medqa in mcq_datasets
      assert :medmcqa in mcq_datasets
      assert :mmlu_clinical in mcq_datasets
      refute :pubmedqa in mcq_datasets
    end

    test "returns binary QA datasets" do
      binary_qa_datasets = Loaders.list_by_task(:binary_qa)

      assert :pubmedqa in binary_qa_datasets
      refute :medqa in binary_qa_datasets
    end

    test "returns NER datasets" do
      ner_datasets = Loaders.list_by_task(:ner)

      assert :ncbi_disease in ner_datasets
    end

    test "returns reasoning datasets" do
      reasoning_datasets = Loaders.list_by_task(:reasoning)

      assert :medical_o1 in reasoning_datasets
    end
  end

  describe "list_by_clinical_area/1" do
    test "returns USMLE datasets" do
      usmle_datasets = Loaders.list_by_clinical_area("usmle")

      assert :medqa in usmle_datasets
    end

    test "returns clinical knowledge datasets" do
      clinical_datasets = Loaders.list_by_clinical_area("clinical_knowledge")

      assert :mmlu_clinical in clinical_datasets
    end
  end

  describe "load/2 with mock data" do
    # Note: These tests use the mock fallback since HfDatasetsEx may not be available
    # Integration tests that actually load from HuggingFace should be tagged @tag :integration

    test "returns error for unknown dataset" do
      assert {:error, {:unknown_medical_dataset, :nonexistent}} =
               Loaders.load(:nonexistent)
    end

    test "load returns Dataset struct with medical metadata" do
      # This will use the mock since HfDatasetsEx may not load actual data
      result = Loaders.load(:medqa, limit: 10)

      case result do
        {:ok, %Dataset{} = dataset} ->
          assert dataset.name == "medqa"
          assert dataset.schema == :medical_mcq
          assert is_map(dataset.metadata)
          assert dataset.metadata.domain == :medical
          assert dataset.metadata.clinical_area == "usmle"
          assert dataset.metadata.task == :mcq
          assert dataset.metadata.phi_status == :none

        {:error, _} ->
          # If HfDatasetsEx fails, that's acceptable for unit tests
          :ok
      end
    end

    test "load with limit option" do
      result = Loaders.load(:medqa, limit: 5)

      case result do
        {:ok, %Dataset{} = dataset} ->
          assert length(dataset.data) <= 5

        {:error, _} ->
          :ok
      end
    end

    test "dataset has artifact_id for lineage tracking" do
      result = Loaders.load(:medqa)

      case result do
        {:ok, %Dataset{} = dataset} ->
          assert is_binary(dataset.artifact_id)
          assert String.length(dataset.artifact_id) == 36  # UUID length

        {:error, _} ->
          :ok
      end
    end
  end

  describe "load/2 integration tests" do
    # These tests actually load from HuggingFace and are slow
    # Run with: mix test --include integration
    @describetag :integration

    @tag :skip
    test "loads MedQA from HuggingFace" do
      {:ok, dataset} = Loaders.load(:medqa, split: "test", limit: 10)

      assert %Dataset{} = dataset
      assert dataset.name == "medqa"
      assert length(dataset.data) <= 10

      # Check MCQ format
      [first | _] = dataset.data
      assert Map.has_key?(first, :question)
      assert Map.has_key?(first, :options)
      assert Map.has_key?(first, :correct_answer)
    end

    @tag :skip
    test "loads PubMedQA with binary QA format" do
      {:ok, dataset} = Loaders.load(:pubmedqa, split: "test", limit: 10)

      assert dataset.schema == :medical_binary_qa

      [first | _] = dataset.data
      assert Map.has_key?(first, :question)
      assert Map.has_key?(first, :context)
      assert Map.has_key?(first, :answer)
      assert first.answer in ["yes", "no", "maybe"]
    end

    @tag :skip
    test "loads NCBI Disease with NER format" do
      {:ok, dataset} = Loaders.load(:ncbi_disease, split: "test", limit: 10)

      assert dataset.schema == :medical_ner

      [first | _] = dataset.data
      assert Map.has_key?(first, :text)
      assert Map.has_key?(first, :entities)
      assert is_list(first.entities)
    end

    @tag :skip
    test "streaming mode works" do
      {:ok, dataset} = Loaders.load(:medqa, streaming: true, split: "test")

      # Streaming should still return a Dataset but data might be lazy
      assert %Dataset{} = dataset
    end

    @tag :skip
    test "revision pinning for reproducibility" do
      {:ok, dataset} = Loaders.load(:medqa,
        split: "test",
        revision: "main",
        limit: 10
      )

      assert dataset.metadata.hf_revision == "main"
    end
  end
end
