defmodule MedlumLlm.Labeling.ClinicalDocumentTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Labeling.ClinicalDocument

  describe "document_types/0" do
    test "returns all document types" do
      types = ClinicalDocument.document_types()

      assert types == [
               :discharge_summary,
               :lab_report,
               :consultation,
               :imaging,
               :medication_list,
               :progress_note
             ]
    end
  end

  describe "valid_document_type?/1" do
    test "returns true for valid types" do
      for type <- [
            :discharge_summary,
            :lab_report,
            :consultation,
            :imaging,
            :medication_list,
            :progress_note
          ] do
        assert ClinicalDocument.valid_document_type?(type)
      end
    end

    test "returns false for invalid types" do
      refute ClinicalDocument.valid_document_type?(:unknown)
      refute ClinicalDocument.valid_document_type?(:radiology)
    end

    test "returns false for non-atom input" do
      refute ClinicalDocument.valid_document_type?("discharge_summary")
    end
  end

  describe "ontology_keys/0" do
    test "returns all ontology keys" do
      keys = ClinicalDocument.ontology_keys()
      assert keys == [:snomed_ct, :icd10, :rxnorm, :loinc]
    end
  end

  describe "empty_ontology_codes/0" do
    test "returns map with all keys as empty lists" do
      codes = ClinicalDocument.empty_ontology_codes()

      assert codes == %{
               snomed_ct: [],
               icd10: [],
               rxnorm: [],
               loinc: []
             }
    end
  end

  describe "validate/1" do
    test "validates complete document" do
      doc = %{
        type: :discharge_summary,
        content: "Patient discharged on metformin...",
        date: ~D[2026-01-15],
        provider_type: "endocrinology",
        ontology_codes: %{
          snomed_ct: ["44054006"],
          icd10: ["E11.9"],
          rxnorm: ["861004"],
          loinc: []
        }
      }

      assert {:ok, validated} = ClinicalDocument.validate(doc)
      assert validated.type == :discharge_summary
      assert validated.content == "Patient discharged on metformin..."
      assert validated.date == ~D[2026-01-15]
      assert validated.provider_type == "endocrinology"
      assert validated.ontology_codes.icd10 == ["E11.9"]
    end

    test "validates document with nil date and provider_type" do
      doc = %{
        type: :lab_report,
        content: "HbA1c: 7.2%",
        date: nil,
        provider_type: nil,
        ontology_codes: ClinicalDocument.empty_ontology_codes()
      }

      assert {:ok, validated} = ClinicalDocument.validate(doc)
      assert validated.date == nil
      assert validated.provider_type == nil
    end

    test "returns error for missing type" do
      doc = %{
        content: "Content",
        date: nil,
        provider_type: nil,
        ontology_codes: ClinicalDocument.empty_ontology_codes()
      }

      assert {:error, :missing_type} = ClinicalDocument.validate(doc)
    end

    test "returns error for invalid document type" do
      doc = %{
        type: :unknown,
        content: "Content",
        date: nil,
        provider_type: nil,
        ontology_codes: ClinicalDocument.empty_ontology_codes()
      }

      assert {:error, {:invalid_document_type, :unknown}} = ClinicalDocument.validate(doc)
    end

    test "returns error for empty content" do
      doc = %{
        type: :lab_report,
        content: "",
        date: nil,
        provider_type: nil,
        ontology_codes: ClinicalDocument.empty_ontology_codes()
      }

      assert {:error, :empty_content} = ClinicalDocument.validate(doc)
    end

    test "returns error for missing ontology key" do
      doc = %{
        type: :lab_report,
        content: "Content",
        date: nil,
        provider_type: nil,
        ontology_codes: %{
          snomed_ct: [],
          icd10: []
          # missing rxnorm and loinc
        }
      }

      assert {:error, {:missing_ontology_key, :rxnorm}} = ClinicalDocument.validate(doc)
    end

    test "returns error for non-string ontology codes" do
      doc = %{
        type: :lab_report,
        content: "Content",
        date: nil,
        provider_type: nil,
        ontology_codes: %{
          snomed_ct: [123],
          icd10: [],
          rxnorm: [],
          loinc: []
        }
      }

      assert {:error, {:ontology_codes_not_string_list, :snomed_ct}} =
               ClinicalDocument.validate(doc)
    end
  end

  describe "validate!/1" do
    test "returns validated document" do
      doc = %{
        type: :consultation,
        content: "Follow-up visit",
        date: ~D[2026-01-20],
        provider_type: "cardiology",
        ontology_codes: ClinicalDocument.empty_ontology_codes()
      }

      assert validated = ClinicalDocument.validate!(doc)
      assert validated.type == :consultation
    end

    test "raises ArgumentError for invalid document" do
      assert_raise ArgumentError, ~r/Invalid clinical document/, fn ->
        ClinicalDocument.validate!(%{type: :unknown})
      end
    end
  end

  describe "serialize/1" do
    test "converts document to JSON-friendly map" do
      doc = %{
        type: :discharge_summary,
        content: "Patient discharged...",
        date: ~D[2026-01-15],
        provider_type: "internal_medicine",
        ontology_codes: %{
          snomed_ct: ["44054006"],
          icd10: ["E11.9"],
          rxnorm: [],
          loinc: []
        }
      }

      serialized = ClinicalDocument.serialize(doc)

      assert serialized["type"] == "discharge_summary"
      assert serialized["content"] == "Patient discharged..."
      assert serialized["date"] == "2026-01-15"
      assert serialized["provider_type"] == "internal_medicine"
      assert serialized["ontology_codes"]["snomed_ct"] == ["44054006"]
    end

    test "serializes nil date as nil" do
      doc = %{
        type: :lab_report,
        content: "Lab results",
        date: nil,
        provider_type: nil,
        ontology_codes: ClinicalDocument.empty_ontology_codes()
      }

      serialized = ClinicalDocument.serialize(doc)

      assert serialized["date"] == nil
      assert serialized["provider_type"] == nil
    end
  end

  describe "deserialize/1" do
    test "parses JSON-friendly map to document" do
      data = %{
        "type" => "lab_report",
        "content" => "HbA1c: 7.2%",
        "date" => "2026-01-14",
        "provider_type" => "laboratory",
        "ontology_codes" => %{
          "loinc" => ["4548-4"],
          "snomed_ct" => [],
          "icd10" => [],
          "rxnorm" => []
        }
      }

      assert {:ok, doc} = ClinicalDocument.deserialize(data)
      assert doc.type == :lab_report
      assert doc.content == "HbA1c: 7.2%"
      assert doc.date == ~D[2026-01-14]
      assert doc.ontology_codes.loinc == ["4548-4"]
    end

    test "parses nil date" do
      data = %{
        "type" => "consultation",
        "content" => "Visit notes",
        "date" => nil,
        "provider_type" => nil,
        "ontology_codes" => %{
          "snomed_ct" => [],
          "icd10" => [],
          "rxnorm" => [],
          "loinc" => []
        }
      }

      assert {:ok, doc} = ClinicalDocument.deserialize(data)
      assert doc.date == nil
    end

    test "returns error for invalid date format" do
      data = %{
        "type" => "lab_report",
        "content" => "Content",
        "date" => "invalid-date",
        "provider_type" => nil,
        "ontology_codes" => %{"snomed_ct" => [], "icd10" => [], "rxnorm" => [], "loinc" => []}
      }

      assert {:error, {:invalid_date_format, "invalid-date"}} = ClinicalDocument.deserialize(data)
    end

    test "returns error for invalid document type string" do
      data = %{
        "type" => "unknown_type",
        "content" => "Content",
        "date" => nil,
        "provider_type" => nil,
        "ontology_codes" => %{"snomed_ct" => [], "icd10" => [], "rxnorm" => [], "loinc" => []}
      }

      assert {:error, {:invalid_document_type, "unknown_type"}} =
               ClinicalDocument.deserialize(data)
    end
  end

  describe "serialize/deserialize round-trip" do
    test "preserves document through round-trip" do
      original = %{
        type: :imaging,
        content: "CT scan findings...",
        date: ~D[2026-01-20],
        provider_type: "radiology",
        ontology_codes: %{
          snomed_ct: ["123456"],
          icd10: ["R93.8"],
          rxnorm: [],
          loinc: ["12345-6"]
        }
      }

      serialized = ClinicalDocument.serialize(original)
      assert {:ok, deserialized} = ClinicalDocument.deserialize(serialized)

      assert deserialized.type == original.type
      assert deserialized.content == original.content
      assert deserialized.date == original.date
      assert deserialized.provider_type == original.provider_type
      assert deserialized.ontology_codes == original.ontology_codes
    end
  end
end
