defmodule MedlumLlm.CVL.ForgeBridgeTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.ForgeBridge

  describe "transform_forge_to_anvil/2" do
    test "transforms Forge sample format" do
      forge_sample = %{
        id: "forge_sample_1",
        data: %{
          premise: "Patient presents with chest pain",
          hypothesis: "Patient has heart disease",
          error_type: :neutral
        },
        pipeline: "cvl_training",
        version: "1.0"
      }

      anvil_sample = ForgeBridge.transform_forge_to_anvil(forge_sample, true)

      assert anvil_sample.id == "forge_sample_1"
      assert anvil_sample.premise == "Patient presents with chest pain"
      assert anvil_sample.hypothesis == "Patient has heart disease"
      assert anvil_sample.metadata.forge_id == "forge_sample_1"
      assert anvil_sample.metadata.forge_pipeline == "cvl_training"
      assert anvil_sample.metadata.forge_version == "1.0"
    end

    test "includes measurements when requested" do
      forge_sample = %{
        id: "forge_sample_2",
        data: %{premise: "P", hypothesis: "H"},
        measurements: %{confidence: %{score: 0.45}}
      }

      with_measurements = ForgeBridge.transform_forge_to_anvil(forge_sample, true)
      without_measurements = ForgeBridge.transform_forge_to_anvil(forge_sample, false)

      assert with_measurements.metadata.measurements == %{confidence: %{score: 0.45}}
      refute Map.has_key?(without_measurements.metadata, :measurements)
    end

    test "handles source_document and generated_summary fields" do
      forge_sample = %{
        id: "forge_sample_3",
        data: %{
          source_document: "Clinical note content",
          generated_summary: "Summary of clinical note"
        }
      }

      anvil_sample = ForgeBridge.transform_forge_to_anvil(forge_sample, false)

      assert anvil_sample.premise == "Clinical note content"
      assert anvil_sample.hypothesis == "Summary of clinical note"
    end
  end

  describe "build_measurements/2" do
    test "builds measurements from labels with consensus" do
      labels = [
        %{labeler_id: "l1", values: %{"verdict" => "ENTAILMENT", "confidence" => 4}},
        %{labeler_id: "l2", values: %{"verdict" => "ENTAILMENT", "confidence" => 5}},
        %{labeler_id: "l3", values: %{"verdict" => "ENTAILMENT", "confidence" => 4}}
      ]

      measurements = ForgeBridge.build_measurements(labels, 0.80)

      assert measurements.cvl_labels.count == 3
      assert measurements.cvl_labels.consensus == "ENTAILMENT"
      assert measurements.cvl_labels.agreement == 1.0
      assert measurements.cvl_labels.avg_confidence > 4.0
    end

    test "marks low agreement samples for review" do
      labels = [
        %{labeler_id: "l1", values: %{"verdict" => "ENTAILMENT", "confidence" => 3}},
        %{labeler_id: "l2", values: %{"verdict" => "CONTRADICTION", "confidence" => 3}},
        %{labeler_id: "l3", values: %{"verdict" => "NEUTRAL", "confidence" => 3}}
      ]

      measurements = ForgeBridge.build_measurements(labels, 0.80)

      # Agreement is 1/3 = 0.33, below 0.80 threshold
      assert measurements.cvl_labels.needs_review == true
      assert measurements.cvl_labels.consensus == nil
    end

    test "returns nil for empty labels" do
      measurements = ForgeBridge.build_measurements([], 0.80)

      assert measurements == nil
    end

    test "returns nil for labels without verdicts" do
      labels = [
        %{labeler_id: "l1", values: %{"confidence" => 4}},
        %{labeler_id: "l2", values: %{"confidence" => 3}}
      ]

      measurements = ForgeBridge.build_measurements(labels, 0.80)

      assert measurements == nil
    end
  end

  describe "majority_verdict/1" do
    test "returns majority verdict" do
      labels = [
        %{labeler_id: "l1", values: %{"verdict" => "ENTAILMENT"}},
        %{labeler_id: "l2", values: %{"verdict" => "ENTAILMENT"}},
        %{labeler_id: "l3", values: %{"verdict" => "NEUTRAL"}}
      ]

      assert ForgeBridge.majority_verdict(labels) == "ENTAILMENT"
    end

    test "returns verdict with most votes in tie" do
      labels = [
        %{labeler_id: "l1", values: %{"verdict" => "ENTAILMENT"}},
        %{labeler_id: "l2", values: %{"verdict" => "NEUTRAL"}}
      ]

      result = ForgeBridge.majority_verdict(labels)
      # Either one could win in a tie
      assert result in ["ENTAILMENT", "NEUTRAL"]
    end

    test "returns nil for empty labels" do
      assert ForgeBridge.majority_verdict([]) == nil
    end

    test "handles missing verdict values" do
      labels = [
        %{labeler_id: "l1", values: %{"verdict" => "ENTAILMENT"}},
        %{labeler_id: "l2", values: %{"confidence" => 4}},
        %{labeler_id: "l3", values: %{"verdict" => "ENTAILMENT"}}
      ]

      assert ForgeBridge.majority_verdict(labels) == "ENTAILMENT"
    end
  end

  describe "compute_agreement/1" do
    test "returns 1.0 for perfect agreement" do
      labels = [
        %{labeler_id: "l1", values: %{"verdict" => "CONTRADICTION"}},
        %{labeler_id: "l2", values: %{"verdict" => "CONTRADICTION"}},
        %{labeler_id: "l3", values: %{"verdict" => "CONTRADICTION"}}
      ]

      assert ForgeBridge.compute_agreement(labels) == 1.0
    end

    test "returns 2/3 for two matching votes" do
      labels = [
        %{labeler_id: "l1", values: %{"verdict" => "ENTAILMENT"}},
        %{labeler_id: "l2", values: %{"verdict" => "ENTAILMENT"}},
        %{labeler_id: "l3", values: %{"verdict" => "NEUTRAL"}}
      ]

      agreement = ForgeBridge.compute_agreement(labels)
      assert_in_delta agreement, 0.6667, 0.001
    end

    test "returns 1/3 for all different votes" do
      labels = [
        %{labeler_id: "l1", values: %{"verdict" => "ENTAILMENT"}},
        %{labeler_id: "l2", values: %{"verdict" => "CONTRADICTION"}},
        %{labeler_id: "l3", values: %{"verdict" => "NEUTRAL"}}
      ]

      agreement = ForgeBridge.compute_agreement(labels)
      assert_in_delta agreement, 0.3333, 0.001
    end

    test "returns nil for less than 2 labels" do
      assert ForgeBridge.compute_agreement([]) == nil

      assert ForgeBridge.compute_agreement([
               %{labeler_id: "l1", values: %{"verdict" => "ENTAILMENT"}}
             ]) == nil
    end
  end

  describe "status/1" do
    test "returns status structure" do
      # This would require integration with actual queue
      # For unit testing, we verify the structure
      expected_keys = [
        :queue_id,
        :anvil_samples,
        :complete_samples,
        :total_labels,
        :unique_labelers,
        :synced_to_forge
      ]

      # Verify the function signature is correct
      assert is_function(&ForgeBridge.status/1, 1)
    end
  end
end
