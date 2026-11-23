defmodule MedOntology.ValidationTest do
  # async: false because SNOMED-CT validation uses mocked client
  use ExUnit.Case, async: false

  import Mox

  setup :verify_on_exit!

  # Clear cache before tests
  setup do
    if :ets.whereis(:snomed_ct_cache) != :undefined do
      :ets.delete_all_objects(:snomed_ct_cache)
    end

    if :ets.whereis(:rxnorm_cache) != :undefined do
      :ets.delete_all_objects(:rxnorm_cache)
    end

    if :ets.whereis(:loinc_cache) != :undefined do
      :ets.delete_all_objects(:loinc_cache)
    end

    :ok
  end

  @diabetes_data %{
    "conceptId" => "44054006",
    "fsn" => %{"term" => "Diabetes mellitus type 2 (disorder)"},
    "pt" => %{"term" => "Type 2 diabetes mellitus"},
    "active" => true,
    "moduleId" => "900000000000207008",
    "definitionStatus" => "FULLY_DEFINED"
  }

  @metformin_props %{
    "propConceptGroup" => %{
      "propConcept" => [
        %{"propName" => "RXCUI", "propValue" => "861004"},
        %{"propName" => "RxNorm Name", "propValue" => "metformin hydrochloride 500 MG Oral Tablet"},
        %{"propName" => "TTY", "propValue" => "SCD"}
      ]
    }
  }

  describe "SNOMED-CT validation" do
    test "valid SCTID returns true when concept exists and is active" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "44054006" -> {:ok, @diabetes_data} end)

      assert MedOntology.SnomedCT.valid?("44054006")
    end

    test "invalid SCTID returns false" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "12345" -> {:error, :not_found} end)

      refute MedOntology.SnomedCT.valid?("12345")
    end

    test "inactive concept returns false" do
      inactive_data = Map.put(@diabetes_data, "active", false)

      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "99999" -> {:ok, inactive_data} end)

      refute MedOntology.SnomedCT.valid?("99999")
    end
  end

  describe "ICD-10 validation" do
    test "valid ICD-10 format" do
      # ICD-10 format: Letter + 2 digits, optionally + . + 1-4 digits
      assert MedOntology.ICD10.valid?("E11")
      assert MedOntology.ICD10.valid?("E11.9")
      assert MedOntology.ICD10.valid?("E11.65")
      assert MedOntology.ICD10.valid?("A00")
      assert MedOntology.ICD10.valid?("Z99.89")
    end

    test "invalid ICD-10 format" do
      refute MedOntology.ICD10.valid?("E1")  # Too short
      refute MedOntology.ICD10.valid?("E111")  # Missing decimal
      refute MedOntology.ICD10.valid?("11.9")  # Missing letter
      refute MedOntology.ICD10.valid?("EE1.9")  # Two letters
      refute MedOntology.ICD10.valid?("E11.99999")  # Too many decimal digits
    end
  end

  describe "RxNorm validation" do
    test "valid RxCUI returns true when concept exists" do
      # RxNorm validation checks both format (numeric) and existence
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "861004" -> {:ok, @metformin_props} end)

      assert MedOntology.RxNorm.valid?("861004")
    end

    test "valid format but non-existent RxCUI returns false" do
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "999999999" -> {:error, :not_found} end)

      refute MedOntology.RxNorm.valid?("999999999")
    end

    test "invalid RxCUI format returns false without API call" do
      # Non-numeric codes are rejected without API call
      refute MedOntology.RxNorm.valid?("ABC123")
      refute MedOntology.RxNorm.valid?("12-34")
      refute MedOntology.RxNorm.valid?("12.34")
      refute MedOntology.RxNorm.valid?("")
    end
  end

  @glucose_data %{
    "display" => "Glucose [Mass/volume] in Serum or Plasma",
    "COMPONENT" => "Glucose",
    "PROPERTY" => "MCnc",
    "CLASS" => "CHEM"
  }

  describe "LOINC validation" do
    test "valid LOINC format and existing code" do
      # LOINC validation now checks both format AND existence
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "2345-7" -> {:ok, @glucose_data} end)
      |> expect(:get_concept, fn "1-1" -> {:ok, %{"display" => "Test"}} end)
      |> expect(:get_concept, fn "718-7" -> {:ok, %{"display" => "Hemoglobin"}} end)
      |> expect(:get_concept, fn "4548-4" -> {:ok, %{"display" => "Hemoglobin A1c"}} end)

      assert MedOntology.LOINC.valid?("2345-7")
      assert MedOntology.LOINC.valid?("1-1")
      assert MedOntology.LOINC.valid?("718-7")
      assert MedOntology.LOINC.valid?("4548-4")
    end

    test "invalid LOINC format returns false without API call" do
      refute MedOntology.LOINC.valid?("2345")  # Missing check digit
      refute MedOntology.LOINC.valid?("ABC-1")  # Letters
      refute MedOntology.LOINC.valid?("2345-77")  # Multiple check digits
      refute MedOntology.LOINC.valid?("-7")  # Missing number
    end

    test "valid format but non-existent LOINC code returns false" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "9999-9" -> {:error, :not_found} end)

      refute MedOntology.LOINC.valid?("9999-9")
    end
  end

  describe "unified validation" do
    test "validates SNOMED-CT via unified API" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "44054006" -> {:ok, @diabetes_data} end)

      assert MedOntology.valid?(:snomed_ct, "44054006")
    end

    test "validates other ontologies via unified API" do
      # ICD-10 does format-based validation (no API call needed)
      assert MedOntology.valid?(:icd10, "E11.9")

      # LOINC now validates format AND existence, so mock needed
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "2345-7" -> {:ok, @glucose_data} end)

      assert MedOntology.valid?(:loinc, "2345-7")

      # RxNorm validates format AND existence, so mock needed
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "861004" -> {:ok, @metformin_props} end)

      assert MedOntology.valid?(:rxnorm, "861004")
    end

    test "rejects invalid ontology" do
      refute MedOntology.valid?(:unknown, "12345")
    end
  end
end
