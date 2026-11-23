defmodule MedlumLlm.Datasets.CVLTrainingTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Datasets.CVLTraining
  alias DatasetsEx.Dataset

  @sample_positive %{
    premise: "The patient is on metformin 500mg twice daily.",
    hypothesis: "The patient takes metformin 500mg BID.",
    evidence: ["Dose matches: 500mg", "Frequency matches: twice daily = BID"],
    ontology_codes: ["861004"]
  }

  @sample_negative %{
    premise: "The patient is on metformin 500mg twice daily.",
    hypothesis: "The patient takes metformin 1000mg once daily.",
    evidence: ["Dose mismatch: 500mg vs 1000mg", "Frequency mismatch: BID vs daily"],
    ontology_codes: ["861004"]
  }

  @sample_neutral %{
    premise: "The patient is on metformin 500mg twice daily.",
    hypothesis: "The patient may need insulin in the future.",
    evidence: ["No direct relationship to current medication"],
    ontology_codes: []
  }

  describe "agent_types/0" do
    test "returns all CVL agent types" do
      agents = CVLTraining.agent_types()

      assert :medication in agents
      assert :lab in agents
      assert :ontology in agents
      assert :temporal in agents
      assert :differential in agents
      assert length(agents) == 5
    end
  end

  describe "verdict_types/0" do
    test "returns all verdict types" do
      verdicts = CVLTraining.verdict_types()

      assert :entailment in verdicts
      assert :contradiction in verdicts
      assert :neutral in verdicts
      assert length(verdicts) == 3
    end
  end

  describe "validate_sample/1" do
    test "validates valid sample" do
      sample = %{
        premise: "Patient is on aspirin.",
        hypothesis: "Patient takes aspirin daily.",
        verdict: :entailment
      }

      assert {:ok, ^sample} = CVLTraining.validate_sample(sample)
    end

    test "rejects sample missing required fields" do
      sample = %{premise: "Patient is on aspirin."}

      assert {:error, errors} = CVLTraining.validate_sample(sample)
      assert Enum.any?(errors, &String.contains?(&1, "Missing required fields"))
    end

    test "rejects sample with invalid verdict" do
      sample = %{
        premise: "Patient is on aspirin.",
        hypothesis: "Patient takes aspirin.",
        verdict: :invalid_verdict
      }

      assert {:error, errors} = CVLTraining.validate_sample(sample)
      assert Enum.any?(errors, &String.contains?(&1, "Invalid verdict"))
    end

    test "rejects empty premise" do
      sample = %{
        premise: "",
        hypothesis: "Valid hypothesis.",
        verdict: :entailment
      }

      assert {:error, errors} = CVLTraining.validate_sample(sample)
      assert Enum.any?(errors, &String.contains?(&1, "premise"))
    end

    test "rejects empty hypothesis" do
      sample = %{
        premise: "Valid premise.",
        hypothesis: "   ",
        verdict: :entailment
      }

      assert {:error, errors} = CVLTraining.validate_sample(sample)
      assert Enum.any?(errors, &String.contains?(&1, "hypothesis"))
    end
  end

  describe "create/3" do
    test "creates training data for medication agent" do
      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: [@sample_positive],
        negative_samples: [@sample_negative],
        neutral_samples: [@sample_neutral],
        ontology_sources: ["RxNorm_2026AA"]
      )

      assert %Dataset{} = dataset
      assert dataset.schema == :medical_cvl
      assert length(dataset.data) == 3

      # Check metadata
      assert dataset.metadata.agent_type == :medication
      assert dataset.metadata.version == "v1.0.0"
      assert dataset.metadata.ontology_sources == ["RxNorm_2026AA"]

      # Check sample counts
      assert dataset.metadata.sample_counts.entailment == 1
      assert dataset.metadata.sample_counts.contradiction == 1
      assert dataset.metadata.sample_counts.neutral == 1
    end

    test "creates training data for lab agent" do
      {:ok, dataset} = CVLTraining.create(:lab, "v1.0.0",
        positive_samples: [@sample_positive],
        negative_samples: [@sample_negative]
      )

      assert dataset.metadata.agent_type == :lab
    end

    test "returns error when no samples provided" do
      assert {:error, :no_samples_provided} =
               CVLTraining.create(:medication, "v1.0.0", [])
    end

    test "assigns IDs to samples without IDs" do
      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: [@sample_positive]
      )

      [sample | _] = dataset.data
      assert is_binary(sample.id)
      assert String.contains?(sample.id, "medication_v1.0.0")
    end

    test "tags samples with agent type and verdict" do
      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: [@sample_positive],
        negative_samples: [@sample_negative]
      )

      entailment_samples = Enum.filter(dataset.data, &(&1.verdict == :entailment))
      contradiction_samples = Enum.filter(dataset.data, &(&1.verdict == :contradiction))

      assert length(entailment_samples) == 1
      assert length(contradiction_samples) == 1

      [positive | _] = entailment_samples
      assert positive.agent_type == :medication
      assert positive.verdict == :entailment
    end

    test "preserves evidence and ontology codes" do
      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: [@sample_positive]
      )

      [sample | _] = dataset.data
      assert sample.evidence == ["Dose matches: 500mg", "Frequency matches: twice daily = BID"]
      assert sample.ontology_codes == ["861004"]
    end

    test "creates dataset with artifact_id for lineage" do
      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: [@sample_positive]
      )

      assert is_binary(dataset.artifact_id)
    end
  end

  describe "split/2" do
    test "stratified split maintains verdict distribution" do
      # Create dataset with known distribution
      positives = for i <- 1..40, do: Map.put(@sample_positive, :id, "pos_#{i}")
      negatives = for i <- 1..30, do: Map.put(@sample_negative, :id, "neg_#{i}")
      neutrals = for i <- 1..30, do: Map.put(@sample_neutral, :id, "neu_#{i}")

      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: positives,
        negative_samples: negatives,
        neutral_samples: neutrals
      )

      {train, test} = CVLTraining.split(dataset, ratio: 0.8, seed: 42)

      # Check sizes
      assert length(train.data) == 80  # 80% of 100
      assert length(test.data) == 20   # 20% of 100

      # Check stratification maintained approximate ratios
      train_verdicts = Enum.frequencies_by(train.data, & &1.verdict)
      _test_verdicts = Enum.frequencies_by(test.data, & &1.verdict)

      # Allow some variance but ratios should be similar
      assert Map.get(train_verdicts, :entailment, 0) >= 28  # ~32 expected
      assert Map.get(train_verdicts, :contradiction, 0) >= 20  # ~24 expected
    end

    test "split with seed is reproducible" do
      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: for(i <- 1..20, do: Map.put(@sample_positive, :id, "#{i}")),
        negative_samples: for(i <- 1..20, do: Map.put(@sample_negative, :id, "#{i}"))
      )

      {train1, _test1} = CVLTraining.split(dataset, ratio: 0.8, seed: 42)
      {train2, _test2} = CVLTraining.split(dataset, ratio: 0.8, seed: 42)

      assert train1.data == train2.data
    end
  end

  describe "from_eval_failures/4" do
    test "creates training data from medication failures" do
      failures = [
        %{
          id: "fail_1",
          question: "What medication is prescribed?",
          expected: "metformin 500mg BID",
          predicted: "metformin 1000mg daily",
          model_confidence: 0.7,
          error_type: :medication_error,
          error_message: "Dose and frequency mismatch"
        }
      ]

      {:ok, dataset} = CVLTraining.from_eval_failures(:medication, failures, "v1.1.0",
        eval_run_id: "eval_001",
        model: "test_model"
      )

      assert %Dataset{} = dataset
      assert length(dataset.data) == 1

      [sample | _] = dataset.data
      assert sample.verdict == :contradiction
      assert sample.premise == "metformin 500mg BID"
      assert sample.hypothesis == "metformin 1000mg daily"
    end

    test "filters failures by agent type" do
      failures = [
        %{error_type: :medication_error, expected: "med1", predicted: "med2"},
        %{error_type: :lab_error, expected: "lab1", predicted: "lab2"},
        %{error_type: :medication_error, expected: "med3", predicted: "med4"}
      ]

      {:ok, dataset} = CVLTraining.from_eval_failures(:medication, failures, "v1.0.0")

      # Should only include medication errors
      assert length(dataset.data) == 2
    end

    test "returns error when no matching failures" do
      failures = [
        %{error_type: :lab_error, expected: "lab1", predicted: "lab2"}
      ]

      assert {:error, :no_matching_failures} =
               CVLTraining.from_eval_failures(:medication, failures, "v1.0.0")
    end

    test "tracks eval_run_id in metadata" do
      failures = [
        %{error_type: :medication_error, expected: "med1", predicted: "med2"}
      ]

      {:ok, dataset} = CVLTraining.from_eval_failures(:medication, failures, "v1.0.0",
        eval_run_id: "eval_123"
      )

      assert dataset.metadata.eval_run_id == "eval_123"
    end

    test "supports custom transform function" do
      failures = [
        %{custom_field: "custom_value", error_type: :medication_error}
      ]

      custom_transform = fn failure, agent ->
        %{
          id: Ecto.UUID.generate(),
          premise: "Custom premise from #{failure.custom_field}",
          hypothesis: "Custom hypothesis",
          verdict: :contradiction,
          evidence: [],
          ontology_codes: [],
          agent_type: agent,
          confidence: 1.0
        }
      end

      {:ok, dataset} = CVLTraining.from_eval_failures(:medication, failures, "v1.0.0",
        transform_fn: custom_transform
      )

      [sample | _] = dataset.data
      assert sample.premise == "Custom premise from custom_value"
    end
  end

  describe "artifact_ref/2" do
    test "builds artifact reference for lineage" do
      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: [@sample_positive]
      )

      ref = CVLTraining.artifact_ref(dataset)

      assert %LineageIR.ArtifactRef{} = ref
      assert ref.artifact_id == dataset.artifact_id
      assert ref.type == "cvl_training_data"
    end
  end

  describe "lineage_edge/3" do
    test "creates lineage edge between artifacts" do
      source_ref = %LineageIR.ArtifactRef{
        artifact_id: Ecto.UUID.generate(),
        type: "eval_run"
      }

      {:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
        positive_samples: [@sample_positive]
      )
      target_ref = CVLTraining.artifact_ref(dataset)

      edge = CVLTraining.lineage_edge(source_ref, target_ref,
        relationship: "exported_from",
        metadata: %{agent: :medication}
      )

      assert %LineageIR.ProvenanceEdge{} = edge
      assert edge.source_id == source_ref.artifact_id
      assert edge.target_id == target_ref.artifact_id
      assert edge.relationship == "exported_from"
      assert edge.metadata.agent == :medication
    end

    test "uses default relationship derived_from" do
      source_ref = %LineageIR.ArtifactRef{artifact_id: Ecto.UUID.generate()}
      target_ref = %LineageIR.ArtifactRef{artifact_id: Ecto.UUID.generate()}

      edge = CVLTraining.lineage_edge(source_ref, target_ref)

      assert edge.relationship == "derived_from"
    end
  end
end
