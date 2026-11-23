defmodule MedlumLlm.LabelingTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Labeling

  describe "delegated functions" do
    test "verdict_to_label/1 delegates to NLI" do
      assert Labeling.verdict_to_label(:entailment) == "ENTAILMENT"
      assert Labeling.verdict_to_label(:contradiction) == "CONTRADICTION"
      assert Labeling.verdict_to_label(:neutral) == "NEUTRAL"
    end

    test "label_to_verdict/1 delegates to NLI" do
      assert {:ok, :entailment} = Labeling.label_to_verdict("ENTAILMENT")
      assert {:error, :invalid_label} = Labeling.label_to_verdict("INVALID")
    end

    test "valid_labels/0 delegates to NLI" do
      assert Labeling.valid_labels() == ["ENTAILMENT", "CONTRADICTION", "NEUTRAL"]
    end

    test "agent_types/0 delegates to CVL" do
      assert Labeling.agent_types() == [:medication, :lab, :ontology, :temporal, :differential]
    end

    test "document_types/0 delegates to ClinicalDocument" do
      types = Labeling.document_types()
      assert :discharge_summary in types
      assert :lab_report in types
    end

    test "cvl_metric_keys/0 delegates to Metrics" do
      keys = Labeling.cvl_metric_keys()
      assert :hallucination_f1 in keys
      assert :medication_accuracy in keys
    end
  end

  describe "integration: full CVL workflow" do
    alias MedlumLlm.Labeling.{CVL, ClinicalDocument, Schemas, SampleBuilder, LabelBuilder}

    test "builds complete NLI sample and label" do
      # Build sample
      sample =
        SampleBuilder.build_nli_sample(
          "Patient is taking metformin 500mg twice daily.",
          "Patient takes metformin 1000mg once daily.",
          tenant_id: "medlum",
          source_run_id: "eval_001",
          model: "openbio_8b"
        )

      # Verify sample structure
      assert sample.payload["task_type"] == "nli"
      assert sample.tenant_id == "medlum"

      # Get schema
      schema = Schemas.nli_schema(tenant_id: "medlum")
      assert schema.tenant_id == "medlum"
      assert length(schema.fields) == 5

      # Build label
      label =
        LabelBuilder.build_nli_label(%{
          assignment_id: "assign_001",
          sample_id: sample.id,
          queue_id: "cvl_nli_queue",
          tenant_id: "medlum",
          user_id: "annotator_alice",
          verdict: :contradiction,
          time_spent_ms: 45_000,
          confidence: 5,
          reasoning: "Dose mismatch: 500mg BID vs 1000mg daily"
        })

      # Verify label structure
      assert label.values["nli_label"] == "CONTRADICTION"
      assert label.values["confidence"] == 5
      assert label.sample_id == sample.id

      # Both should serialize to JSON
      assert {:ok, _sample_json} = Jason.encode(sample)
      assert {:ok, _label_json} = Jason.encode(label)
    end

    test "builds clinical verification sample with multiple documents" do
      # Create documents
      documents = [
        %{
          type: :discharge_summary,
          content: "Patient discharged on metformin 500mg BID for type 2 diabetes.",
          date: ~D[2026-01-15],
          provider_type: "endocrinology",
          ontology_codes: %{
            snomed_ct: ["44054006"],
            icd10: ["E11.9"],
            rxnorm: ["861004"],
            loinc: []
          }
        },
        %{
          type: :lab_report,
          content: "HbA1c: 7.2% (reference: 4.0-5.6%)",
          date: ~D[2026-01-14],
          provider_type: "laboratory",
          ontology_codes: %{
            snomed_ct: [],
            icd10: [],
            rxnorm: [],
            loinc: ["4548-4"]
          }
        }
      ]

      # Build sample
      sample =
        SampleBuilder.build_clinical_sample(
          documents,
          "Patient has well-controlled type 2 diabetes on metformin 1000mg daily.",
          claims: [%{"text" => "metformin 1000mg daily", "span" => [45, 67]}]
        )

      # Verify payload structure
      assert sample.payload["task_type"] == "clinical_verification"
      assert sample.payload["patient_context"]["document_count"] == 2

      # Verify ontology codes aggregated in metadata
      annotations = sample.metadata["ontology_annotations"]
      assert "44054006" in annotations["snomed_ct"]
      assert "E11.9" in annotations["icd10"]
      assert "861004" in annotations["rxnorm"]
      assert "4548-4" in annotations["loinc"]

      assert {:ok, _json} = Jason.encode(sample)
    end

    test "builds multi-agent verification labels" do
      sample = SampleBuilder.build_nli_sample("premise", "hypothesis")

      # Medication agent verdict
      med_verdict = %{
        verdict: :contradiction,
        confidence: 0.92,
        evidence: ["Dose mismatch: 500mg vs 1000mg"],
        ontology_codes: ["861004"]
      }

      {:ok, validated_med} = CVL.validate_agent_verdict(med_verdict)

      med_label =
        LabelBuilder.build_agent_label(
          :medication,
          validated_med,
          assignment_id: "assign_001",
          sample_id: sample.id,
          queue_id: "agent_queue",
          tenant_id: "medlum",
          agent_id: "medication_agent_v1",
          time_spent_ms: 150
        )

      # Lab agent verdict
      lab_verdict = %{
        verdict: :entailment,
        confidence: 0.88,
        evidence: ["HbA1c value matches"],
        ontology_codes: ["4548-4"]
      }

      {:ok, validated_lab} = CVL.validate_agent_verdict(lab_verdict)

      lab_label =
        LabelBuilder.build_agent_label(
          :lab,
          validated_lab,
          assignment_id: "assign_001",
          sample_id: sample.id,
          queue_id: "agent_queue",
          tenant_id: "medlum",
          agent_id: "lab_agent_v1",
          time_spent_ms: 120
        )

      # Verify agent labels
      assert med_label.user_id == "agent:medication_agent_v1"
      assert med_label.values["verdict"] == "CONTRADICTION"
      assert med_label.metadata["is_agent_label"] == true

      assert lab_label.user_id == "agent:lab_agent_v1"
      assert lab_label.values["verdict"] == "ENTAILMENT"

      # Build consensus
      consensus = %{
        agent_verdicts: %{
          medication: validated_med,
          lab: validated_lab
        },
        consensus_verdict: :contradiction,
        consensus_method: :weighted_vote,
        dissent_count: 1
      }

      consensus_label =
        LabelBuilder.build_consensus_label(
          consensus,
          assignment_id: "assign_001",
          sample_id: sample.id,
          queue_id: "consensus_queue",
          tenant_id: "medlum",
          time_spent_ms: 300
        )

      assert consensus_label.user_id == "agent:cvl_consensus"
      assert consensus_label.values["consensus_verdict"] == "CONTRADICTION"
      assert consensus_label.values["dissent_count"] == 1

      # All labels should serialize
      assert {:ok, _} = Jason.encode(med_label)
      assert {:ok, _} = Jason.encode(lab_label)
      assert {:ok, _} = Jason.encode(consensus_label)
    end

    test "clinical document serialize/deserialize round-trip" do
      original = %{
        type: :discharge_summary,
        content: "Patient discharged...",
        date: ~D[2026-01-15],
        provider_type: "cardiology",
        ontology_codes: %{
          snomed_ct: ["44054006"],
          icd10: ["E11.9"],
          rxnorm: ["861004"],
          loinc: []
        }
      }

      {:ok, validated} = ClinicalDocument.validate(original)
      serialized = ClinicalDocument.serialize(validated)
      {:ok, deserialized} = ClinicalDocument.deserialize(serialized)

      assert deserialized.type == original.type
      assert deserialized.content == original.content
      assert deserialized.date == original.date
      assert deserialized.provider_type == original.provider_type
      assert deserialized.ontology_codes == original.ontology_codes
    end
  end
end
