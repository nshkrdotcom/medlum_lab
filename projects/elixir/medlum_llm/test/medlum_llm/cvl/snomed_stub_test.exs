defmodule MedlumLlm.CVL.SNOMEDStubTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.SNOMEDStub

  describe "lookup/1" do
    test "finds type 2 diabetes" do
      assert {:ok, "44054006"} = SNOMEDStub.lookup("type 2 diabetes mellitus")
    end

    test "finds type 2 diabetes variant" do
      assert {:ok, "44054006"} = SNOMEDStub.lookup("type 2 diabetes")
    end

    test "finds hypertension" do
      assert {:ok, "38341003"} = SNOMEDStub.lookup("hypertension")
    end

    test "finds myocardial infarction" do
      assert {:ok, "22298006"} = SNOMEDStub.lookup("myocardial infarction")
    end

    test "finds heart attack as MI" do
      assert {:ok, "22298006"} = SNOMEDStub.lookup("heart attack")
    end

    test "finds mi abbreviation" do
      assert {:ok, "22298006"} = SNOMEDStub.lookup("mi")
    end

    test "finds pneumonia" do
      assert {:ok, "233604007"} = SNOMEDStub.lookup("pneumonia")
    end

    test "finds congestive heart failure" do
      assert {:ok, "42343007"} = SNOMEDStub.lookup("congestive heart failure")
    end

    test "finds CHF abbreviation" do
      assert {:ok, "42343007"} = SNOMEDStub.lookup("chf")
    end

    test "finds chronic kidney disease" do
      assert {:ok, "709044004"} = SNOMEDStub.lookup("chronic kidney disease")
    end

    test "finds CKD abbreviation" do
      assert {:ok, "709044004"} = SNOMEDStub.lookup("ckd")
    end

    test "finds asthma" do
      assert {:ok, "195967001"} = SNOMEDStub.lookup("asthma")
    end

    test "finds COPD" do
      assert {:ok, "13645005"} = SNOMEDStub.lookup("copd")
    end

    test "finds atrial fibrillation" do
      assert {:ok, "49436004"} = SNOMEDStub.lookup("atrial fibrillation")
    end

    test "finds stroke" do
      assert {:ok, "230690007"} = SNOMEDStub.lookup("stroke")
    end

    test "returns error for unknown diagnosis" do
      assert {:error, :not_found} = SNOMEDStub.lookup("madeupitis")
    end

    test "normalizes case" do
      assert {:ok, "38341003"} = SNOMEDStub.lookup("HYPERTENSION")
      assert {:ok, "38341003"} = SNOMEDStub.lookup("Hypertension")
    end

    test "trims whitespace" do
      assert {:ok, "38341003"} = SNOMEDStub.lookup("  hypertension  ")
    end
  end

  describe "lookup_finding/1" do
    test "finds chest pain" do
      assert {:ok, "29857009"} = SNOMEDStub.lookup_finding("chest pain")
    end

    test "finds dyspnea" do
      assert {:ok, "267036007"} = SNOMEDStub.lookup_finding("dyspnea")
    end

    test "finds shortness of breath as dyspnea" do
      assert {:ok, "267036007"} = SNOMEDStub.lookup_finding("shortness of breath")
    end

    test "finds fever" do
      assert {:ok, "386661006"} = SNOMEDStub.lookup_finding("fever")
    end

    test "finds cough" do
      assert {:ok, "49727002"} = SNOMEDStub.lookup_finding("cough")
    end

    test "finds headache" do
      assert {:ok, "25064002"} = SNOMEDStub.lookup_finding("headache")
    end

    test "finds fatigue" do
      assert {:ok, "84229001"} = SNOMEDStub.lookup_finding("fatigue")
    end

    test "finds edema" do
      assert {:ok, "79654002"} = SNOMEDStub.lookup_finding("edema")
    end

    test "finds palpitations" do
      assert {:ok, "80313002"} = SNOMEDStub.lookup_finding("palpitations")
    end

    test "returns error for unknown finding" do
      assert {:error, :not_found} = SNOMEDStub.lookup_finding("unknownsymptom")
    end
  end

  describe "lookup_procedure/1" do
    test "finds CABG" do
      assert {:ok, "232717009"} = SNOMEDStub.lookup_procedure("cabg")
    end

    test "finds coronary artery bypass" do
      assert {:ok, "232717009"} = SNOMEDStub.lookup_procedure("coronary artery bypass")
    end

    test "finds angioplasty" do
      assert {:ok, "41339005"} = SNOMEDStub.lookup_procedure("angioplasty")
    end

    test "finds PCI" do
      assert {:ok, "415070008"} = SNOMEDStub.lookup_procedure("pci")
    end

    test "finds appendectomy" do
      assert {:ok, "80146002"} = SNOMEDStub.lookup_procedure("appendectomy")
    end

    test "finds dialysis" do
      assert {:ok, "108241001"} = SNOMEDStub.lookup_procedure("dialysis")
    end

    test "returns error for unknown procedure" do
      assert {:error, :not_found} = SNOMEDStub.lookup_procedure("unknownprocedure")
    end
  end

  describe "to_icd10/1" do
    test "maps type 2 diabetes to ICD-10" do
      assert {:ok, ["E11.9"]} = SNOMEDStub.to_icd10("44054006")
    end

    test "maps hypertension to ICD-10" do
      assert {:ok, ["I10"]} = SNOMEDStub.to_icd10("38341003")
    end

    test "maps myocardial infarction to ICD-10" do
      assert {:ok, ["I21.9"]} = SNOMEDStub.to_icd10("22298006")
    end

    test "maps pneumonia to ICD-10" do
      assert {:ok, ["J18.9"]} = SNOMEDStub.to_icd10("233604007")
    end

    test "returns error for unknown SNOMED ID" do
      assert {:error, :no_mapping} = SNOMEDStub.to_icd10("99999999")
    end
  end

  describe "is_associated?/2" do
    test "chest pain associated with myocardial infarction" do
      assert {:ok, true} = SNOMEDStub.is_associated?("chest pain", "myocardial infarction")
    end

    test "dyspnea associated with myocardial infarction" do
      assert {:ok, true} = SNOMEDStub.is_associated?("dyspnea", "myocardial infarction")
    end

    test "increased thirst associated with type 2 diabetes" do
      assert {:ok, true} = SNOMEDStub.is_associated?("increased thirst", "type 2 diabetes mellitus")
    end

    test "cough associated with pneumonia" do
      assert {:ok, true} = SNOMEDStub.is_associated?("cough", "pneumonia")
    end

    test "edema associated with congestive heart failure" do
      assert {:ok, true} = SNOMEDStub.is_associated?("edema", "congestive heart failure")
    end

    test "headache not typically associated with diabetes" do
      assert {:ok, false} = SNOMEDStub.is_associated?("headache", "type 2 diabetes mellitus")
    end

    test "returns error for unknown diagnosis" do
      assert {:error, :no_data} = SNOMEDStub.is_associated?("chest pain", "unknowncondition")
    end
  end

  describe "semantic_relevance/2" do
    test "high relevance when chief complaint matches related findings" do
      assert {:ok, score} =
               SNOMEDStub.semantic_relevance("44054006", "patient has increased thirst and polyuria")

      assert score > 0.5
    end

    test "low relevance when chief complaint doesn't match" do
      assert {:ok, score} =
               SNOMEDStub.semantic_relevance("44054006", "patient has back pain and nausea")

      assert score < 0.3
    end

    test "returns error for unknown SNOMED ID" do
      assert {:error, :no_semantic_data} = SNOMEDStub.semantic_relevance("99999999", "anything")
    end
  end

  describe "semantic_category/1" do
    test "diabetes is metabolic" do
      assert {:ok, "metabolic"} = SNOMEDStub.semantic_category("44054006")
    end

    test "hypertension is cardiovascular" do
      assert {:ok, "cardiovascular"} = SNOMEDStub.semantic_category("38341003")
    end

    test "pneumonia is respiratory" do
      assert {:ok, "respiratory"} = SNOMEDStub.semantic_category("233604007")
    end

    test "CKD is renal" do
      assert {:ok, "renal"} = SNOMEDStub.semantic_category("709044004")
    end

    test "stroke is neurological" do
      assert {:ok, "neurological"} = SNOMEDStub.semantic_category("230690007")
    end

    test "returns error for unknown SNOMED ID" do
      assert {:error, :not_found} = SNOMEDStub.semantic_category("99999999")
    end
  end

  describe "all_diagnoses/0" do
    test "returns non-empty map" do
      diagnoses = SNOMEDStub.all_diagnoses()
      assert is_map(diagnoses)
      assert map_size(diagnoses) > 0
    end

    test "all diagnoses have snomed_id" do
      diagnoses = SNOMEDStub.all_diagnoses()

      Enum.each(diagnoses, fn {_name, info} ->
        assert Map.has_key?(info, :snomed_id)
      end)
    end
  end

  describe "all_findings/0" do
    test "returns non-empty map" do
      findings = SNOMEDStub.all_findings()
      assert is_map(findings)
      assert map_size(findings) > 0
    end
  end

  describe "all_procedures/0" do
    test "returns non-empty map" do
      procedures = SNOMEDStub.all_procedures()
      assert is_map(procedures)
      assert map_size(procedures) > 0
    end
  end
end
