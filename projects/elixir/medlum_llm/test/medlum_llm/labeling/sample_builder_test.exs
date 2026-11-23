defmodule MedlumLlm.Labeling.SampleBuilderTest do
  use ExUnit.Case, async: true

  alias LabelingIR.Sample
  alias MedlumLlm.Labeling.SampleBuilder

  describe "build_nli_sample/3" do
    test "creates valid Sample struct" do
      sample =
        SampleBuilder.build_nli_sample(
          "Patient is on metformin 500mg BID.",
          "Patient takes metformin 1000mg daily."
        )

      assert %Sample{} = sample
      assert String.starts_with?(sample.id, "cvl_")
      assert sample.tenant_id == "medlum"
      assert sample.namespace == "cvl"
      assert sample.pipeline_id == "medlum_cvl_training_v1"
    end

    test "sets correct payload structure" do
      sample =
        SampleBuilder.build_nli_sample(
          "The premise text.",
          "The hypothesis text."
        )

      assert sample.payload["task_type"] == "nli"
      assert sample.payload["premise"] == "The premise text."
      assert sample.payload["hypothesis"] == "The hypothesis text."
    end

    test "accepts tenant_id override" do
      sample =
        SampleBuilder.build_nli_sample(
          "Premise",
          "Hypothesis",
          tenant_id: "custom_tenant"
        )

      assert sample.tenant_id == "custom_tenant"
    end

    test "accepts namespace override" do
      sample =
        SampleBuilder.build_nli_sample(
          "Premise",
          "Hypothesis",
          namespace: "training"
        )

      assert sample.namespace == "training"
    end

    test "sets metadata with source_run_id and model" do
      sample =
        SampleBuilder.build_nli_sample(
          "Premise",
          "Hypothesis",
          source_run_id: "eval_001",
          model: "openbio_8b",
          model_confidence: 0.85
        )

      assert sample.metadata["source"] == "eval_failure"
      assert sample.metadata["source_run_id"] == "eval_001"
      assert sample.metadata["model"] == "openbio_8b"
      assert sample.metadata["model_confidence"] == 0.85
    end

    test "builds lineage_ref when source_run_id provided" do
      sample =
        SampleBuilder.build_nli_sample(
          "Premise",
          "Hypothesis",
          source_run_id: "eval_001",
          model: "openbio_8b"
        )

      assert sample.lineage_ref["source_type"] == "eval_failure"
      assert sample.lineage_ref["eval_run_id"] == "eval_001"
      assert sample.lineage_ref["model"] == "openbio_8b"
      assert sample.lineage_ref["transformation"] == "cvl_sample_builder_v1"
    end

    test "lineage_ref is nil when no source_run_id" do
      sample = SampleBuilder.build_nli_sample("Premise", "Hypothesis")
      assert sample.lineage_ref == nil
    end

    test "sets created_at timestamp" do
      before = DateTime.utc_now()
      sample = SampleBuilder.build_nli_sample("Premise", "Hypothesis")
      after_time = DateTime.utc_now()

      assert DateTime.compare(sample.created_at, before) in [:gt, :eq]
      assert DateTime.compare(sample.created_at, after_time) in [:lt, :eq]
    end

    test "can be serialized to JSON" do
      sample = SampleBuilder.build_nli_sample("Premise", "Hypothesis")
      assert {:ok, _json} = Jason.encode(sample)
    end
  end

  describe "build_clinical_sample/3" do
    setup do
      documents = [
        %{
          type: :discharge_summary,
          content: "Patient discharged on metformin 500mg BID...",
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
          content: "HbA1c: 7.2%",
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

      %{documents: documents}
    end

    test "creates valid Sample struct", %{documents: documents} do
      sample =
        SampleBuilder.build_clinical_sample(
          documents,
          "Patient has well-controlled diabetes."
        )

      assert %Sample{} = sample
      assert String.starts_with?(sample.id, "cvl_")
      assert sample.tenant_id == "medlum"
    end

    test "sets correct payload structure", %{documents: documents} do
      sample =
        SampleBuilder.build_clinical_sample(
          documents,
          "Generated summary text."
        )

      assert sample.payload["task_type"] == "clinical_verification"
      assert sample.payload["generated_summary"] == "Generated summary text."
      assert sample.payload["patient_context"]["document_count"] == 2
      assert length(sample.payload["patient_context"]["documents"]) == 2
    end

    test "serializes documents correctly", %{documents: documents} do
      sample =
        SampleBuilder.build_clinical_sample(
          documents,
          "Summary"
        )

      [doc1, doc2] = sample.payload["patient_context"]["documents"]

      assert doc1["type"] == "discharge_summary"
      assert doc1["date"] == "2026-01-15"
      assert doc1["provider_type"] == "endocrinology"
      assert doc1["ontology_codes"]["icd10"] == ["E11.9"]

      assert doc2["type"] == "lab_report"
      assert doc2["ontology_codes"]["loinc"] == ["4548-4"]
    end

    test "accepts claims in payload", %{documents: documents} do
      claims = [
        %{"text" => "metformin 1000mg daily", "span" => [45, 67]},
        %{"text" => "well-controlled", "span" => [12, 27]}
      ]

      sample =
        SampleBuilder.build_clinical_sample(
          documents,
          "Summary",
          claims: claims
        )

      assert sample.payload["claims"] == claims
    end

    test "extracts aggregated ontology codes to metadata", %{documents: documents} do
      sample =
        SampleBuilder.build_clinical_sample(
          documents,
          "Summary"
        )

      annotations = sample.metadata["ontology_annotations"]

      assert "44054006" in annotations["snomed_ct"]
      assert "E11.9" in annotations["icd10"]
      assert "861004" in annotations["rxnorm"]
      assert "4548-4" in annotations["loinc"]
    end

    test "can be serialized to JSON", %{documents: documents} do
      sample =
        SampleBuilder.build_clinical_sample(
          documents,
          "Summary"
        )

      assert {:ok, _json} = Jason.encode(sample)
    end
  end

  describe "build_from_eval_failure/2" do
    test "creates NLI sample from MCQ failure" do
      failure = %{
        "question" => "What medication is the patient taking?",
        "predicted" => "metformin 1000mg",
        "correct" => "metformin 500mg BID",
        "task" => "mcq",
        "model" => "openbio_8b"
      }

      sample = SampleBuilder.build_from_eval_failure(failure, run_id: "eval_001")

      assert sample.payload["task_type"] == "nli"
      assert sample.payload["premise"] == "What medication is the patient taking?"
      assert sample.payload["hypothesis"] == "The correct answer is metformin 1000mg."
      assert sample.metadata["correct_answer"] == "metformin 500mg BID"
      assert sample.metadata["model"] == "openbio_8b"
    end

    test "creates NLI sample from binary_qa failure" do
      failure = %{
        "context" => "Patient has diabetes.",
        "predicted" => "yes",
        "task" => "binary_qa"
      }

      sample = SampleBuilder.build_from_eval_failure(failure)

      assert sample.payload["hypothesis"] == "Yes, this is true based on the evidence."
    end

    test "handles binary_qa 'no' prediction" do
      failure = %{
        "context" => "Patient has diabetes.",
        "predicted" => "no",
        "task" => "binary_qa"
      }

      sample = SampleBuilder.build_from_eval_failure(failure)

      assert sample.payload["hypothesis"] == "No, this is false based on the evidence."
    end

    test "handles binary_qa 'maybe' prediction" do
      failure = %{
        "context" => "Patient has diabetes.",
        "predicted" => "maybe",
        "task" => "binary_qa"
      }

      sample = SampleBuilder.build_from_eval_failure(failure)

      assert sample.payload["hypothesis"] == "It is uncertain based on the evidence."
    end

    test "handles unknown task type" do
      failure = %{
        "question" => "Some question",
        "predicted" => "Some answer",
        "task" => "unknown_task"
      }

      sample = SampleBuilder.build_from_eval_failure(failure)

      assert sample.payload["hypothesis"] == "Some answer"
    end

    test "preserves model confidence" do
      failure = %{
        "question" => "Question",
        "predicted" => "Answer",
        "task" => "mcq",
        "model_confidence" => 0.75
      }

      sample = SampleBuilder.build_from_eval_failure(failure)

      assert sample.metadata["model_confidence"] == 0.75
    end
  end

  describe "generate_sample_id/0" do
    test "generates IDs with cvl_ prefix" do
      id = SampleBuilder.generate_sample_id()
      assert String.starts_with?(id, "cvl_")
    end

    test "generates unique IDs" do
      ids = for _ <- 1..100, do: SampleBuilder.generate_sample_id()
      assert length(Enum.uniq(ids)) == 100
    end

    test "generates IDs of consistent length" do
      id = SampleBuilder.generate_sample_id()
      # "cvl_" (4) + 24 hex chars = 28
      assert String.length(id) == 28
    end
  end
end
