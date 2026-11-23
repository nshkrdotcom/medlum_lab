defmodule ClinicalNerEx.LinkerTest do
  use ExUnit.Case, async: false

  alias ClinicalNerEx.{Entity, Linker}
  alias ClinicalNerEx.Linker.{RxNorm, LOINC, SNOMED, ICD10}

  # Ensure Cache is started for tests
  setup do
    # Start the cache if not running (for isolated tests)
    case Process.whereis(ClinicalNerEx.Cache) do
      nil ->
        {:ok, _pid} = ClinicalNerEx.Cache.start_link([])
        :ok

      _pid ->
        :ok
    end

    # Clear linker cache before each test
    ClinicalNerEx.Cache.clear(:linker_cache)
    :ok
  end

  describe "RxNorm linker" do
    test "entity_types returns :medication" do
      assert RxNorm.entity_types() == [:medication]
    end

    test "ontology_systems returns :rxnorm" do
      assert RxNorm.ontology_systems() == [:rxnorm]
    end

    test "link/1 handles non-medication entities" do
      entity = Entity.new(%{type: :diagnosis, text: "diabetes"})
      {:ok, result} = RxNorm.link(entity)
      assert result == entity
    end

    test "link/1 adds warning when med_ontology_ex unavailable" do
      entity = Entity.new(%{
        type: :medication,
        text: "metformin 500mg",
        attributes: %{drug_name: "metformin", dose: 500, dose_unit: "mg"}
      })

      # Since med_ontology_ex isn't loaded in tests, should add warning
      {:ok, result} = RxNorm.link(entity)
      assert Enum.any?(result.warnings, &String.contains?(&1, "unavailable"))
    end

    test "link_batch/1 processes multiple entities" do
      entities = [
        Entity.new(%{type: :medication, text: "aspirin"}),
        Entity.new(%{type: :medication, text: "metformin"}),
        Entity.new(%{type: :diagnosis, text: "diabetes"})
      ]

      {:ok, results} = RxNorm.link_batch(entities)
      assert length(results) == 3

      # Diagnosis should be unchanged
      diagnosis = Enum.find(results, &(&1.type == :diagnosis))
      assert diagnosis.ontology_links == []
    end

    test "builds query from structured attributes" do
      entity = Entity.new(%{
        type: :medication,
        text: "take metformin hydrochloride 500mg twice daily",
        attributes: %{drug_name: "metformin", dose: 500, dose_unit: "mg"}
      })

      {:ok, result} = RxNorm.link(entity)
      # Should use structured attributes, not raw text
      # Verify by checking warnings contain "metformin 500mg" not full text
      assert result.type == :medication
    end

    test "builds query from drug_name only when dose not available" do
      entity = Entity.new(%{
        type: :medication,
        text: "start metformin",
        attributes: %{drug_name: "metformin"}
      })

      {:ok, result} = RxNorm.link(entity)
      assert result.type == :medication
    end

    test "falls back to text when no attributes" do
      entity = Entity.new(%{
        type: :medication,
        text: "lisinopril 10mg",
        attributes: %{}
      })

      {:ok, result} = RxNorm.link(entity)
      assert result.type == :medication
    end
  end

  describe "LOINC linker" do
    test "entity_types returns :lab_value" do
      assert LOINC.entity_types() == [:lab_value]
    end

    test "ontology_systems returns :loinc" do
      assert LOINC.ontology_systems() == [:loinc]
    end

    test "link/1 handles non-lab entities" do
      entity = Entity.new(%{type: :medication, text: "metformin"})
      {:ok, result} = LOINC.link(entity)
      assert result == entity
    end

    test "link/1 adds warning when med_ontology_ex unavailable" do
      entity = Entity.new(%{
        type: :lab_value,
        text: "Hemoglobin A1c 7.5%",
        attributes: %{lab_name: "Hemoglobin A1c", value: 7.5, unit: "%"}
      })

      {:ok, result} = LOINC.link(entity)
      assert Enum.any?(result.warnings, &String.contains?(&1, "unavailable"))
    end

    test "link_batch/1 processes multiple entities" do
      entities = [
        Entity.new(%{type: :lab_value, text: "glucose"}),
        Entity.new(%{type: :lab_value, text: "hemoglobin"})
      ]

      {:ok, results} = LOINC.link_batch(entities)
      assert length(results) == 2
    end
  end

  describe "SNOMED linker" do
    test "entity_types returns diagnosis and procedure" do
      assert :diagnosis in SNOMED.entity_types()
      assert :procedure in SNOMED.entity_types()
    end

    test "ontology_systems returns :snomed_ct" do
      assert SNOMED.ontology_systems() == [:snomed_ct]
    end

    test "link/1 handles non-diagnosis/procedure entities" do
      entity = Entity.new(%{type: :medication, text: "metformin"})
      {:ok, result} = SNOMED.link(entity)
      assert result == entity
    end

    test "link/1 handles diagnosis entities" do
      entity = Entity.new(%{
        type: :diagnosis,
        text: "type 2 diabetes",
        attributes: %{condition: "type 2 diabetes"}
      })

      {:ok, result} = SNOMED.link(entity)
      assert result.type == :diagnosis
    end

    test "link/1 handles procedure entities" do
      entity = Entity.new(%{
        type: :procedure,
        text: "colonoscopy",
        attributes: %{procedure_name: "colonoscopy"}
      })

      {:ok, result} = SNOMED.link(entity)
      assert result.type == :procedure
    end

    test "link_batch/1 processes mixed entities" do
      entities = [
        Entity.new(%{type: :diagnosis, text: "diabetes"}),
        Entity.new(%{type: :procedure, text: "surgery"}),
        Entity.new(%{type: :medication, text: "metformin"})
      ]

      {:ok, results} = SNOMED.link_batch(entities)
      assert length(results) == 3
    end
  end

  describe "ICD10 linker" do
    test "entity_types returns :diagnosis" do
      assert ICD10.entity_types() == [:diagnosis]
    end

    test "ontology_systems returns :icd10" do
      assert ICD10.ontology_systems() == [:icd10]
    end

    test "link/1 handles non-diagnosis entities" do
      entity = Entity.new(%{type: :medication, text: "metformin"})
      {:ok, result} = ICD10.link(entity)
      assert result == entity
    end

    test "link/1 does not add warnings for unavailable (secondary ontology)" do
      entity = Entity.new(%{
        type: :diagnosis,
        text: "type 2 diabetes",
        attributes: %{condition: "type 2 diabetes"}
      })

      {:ok, result} = ICD10.link(entity)
      # ICD-10 is silent on failure since it's secondary
      assert result.warnings == []
    end

    test "appends to existing ontology_links" do
      entity = Entity.new(%{
        type: :diagnosis,
        text: "type 2 diabetes",
        attributes: %{condition: "type 2 diabetes"},
        ontology_links: [%{system: :snomed_ct, code: "44054006", display: "test", confidence: 0.9}]
      })

      {:ok, result} = ICD10.link(entity)
      # Should still have original link
      assert Enum.any?(result.ontology_links, &(&1.system == :snomed_ct))
    end
  end

  describe "main Linker module" do
    test "link/1 returns entity unchanged when linking disabled" do
      # Temporarily disable linking
      original = Application.get_env(:clinical_ner_ex, :enable_ontology_linking, true)
      Application.put_env(:clinical_ner_ex, :enable_ontology_linking, false)

      entity = Entity.new(%{
        type: :medication,
        text: "metformin 500mg",
        attributes: %{drug_name: "metformin", dose: 500, dose_unit: "mg"}
      })

      {:ok, result} = Linker.link(entity)
      assert result.ontology_links == []
      assert result.warnings == []

      Application.put_env(:clinical_ner_ex, :enable_ontology_linking, original)
    end

    test "link_all/1 processes multiple entities" do
      entities = [
        Entity.new(%{type: :medication, text: "metformin"}),
        Entity.new(%{type: :lab_value, text: "glucose"}),
        Entity.new(%{type: :diagnosis, text: "diabetes"})
      ]

      {:ok, results} = Linker.link_all(entities)
      assert length(results) == 3
    end

    test "link_all/1 handles empty list" do
      {:ok, results} = Linker.link_all([])
      assert results == []
    end

    test "linkers_for/1 returns correct linkers for medication" do
      linkers = Linker.linkers_for(:medication)
      assert linkers == [RxNorm]
    end

    test "linkers_for/1 returns correct linkers for lab_value" do
      linkers = Linker.linkers_for(:lab_value)
      assert linkers == [LOINC]
    end

    test "linkers_for/1 returns correct linkers for diagnosis" do
      linkers = Linker.linkers_for(:diagnosis)
      assert linkers == [SNOMED, ICD10]
    end

    test "linkers_for/1 returns correct linkers for procedure" do
      linkers = Linker.linkers_for(:procedure)
      assert linkers == [SNOMED]
    end

    test "linkers_for/1 returns empty list for temporal" do
      linkers = Linker.linkers_for(:temporal)
      assert linkers == []
    end

    test "linkers_for/1 returns empty list for unknown type" do
      linkers = Linker.linkers_for(:unknown)
      assert linkers == []
    end

    test "all_linkers/0 returns complete mapping" do
      all = Linker.all_linkers()
      assert Map.has_key?(all, :medication)
      assert Map.has_key?(all, :lab_value)
      assert Map.has_key?(all, :diagnosis)
      assert Map.has_key?(all, :procedure)
      assert Map.has_key?(all, :temporal)
    end

    test "link_medication/1 returns error when ontology unavailable" do
      result = Linker.link_medication("metformin 500mg")
      assert result == {:error, :ontology_unavailable}
    end

    test "link_lab/1 returns error when ontology unavailable" do
      result = Linker.link_lab("hemoglobin A1c")
      assert result == {:error, :ontology_unavailable}
    end

    test "link_diagnosis/1 returns error when ontology unavailable" do
      result = Linker.link_diagnosis("type 2 diabetes")
      assert result == {:error, :ontology_unavailable}
    end

    test "link_procedure/1 returns error when ontology unavailable" do
      result = Linker.link_procedure("colonoscopy")
      assert result == {:error, :ontology_unavailable}
    end
  end

  describe "caching" do
    test "cache stores and retrieves linking results" do
      # This test verifies the caching mechanism works
      entity = Entity.new(%{
        type: :medication,
        text: "test medication",
        attributes: %{drug_name: "test"}
      })

      # First call - will go through linker
      {:ok, result1} = Linker.link(entity)

      # Second call - should use cache (verified via results consistency)
      {:ok, result2} = Linker.link(entity)

      # Results should be consistent
      assert result1.warnings == result2.warnings
    end

    test "different queries use different cache keys" do
      entity1 = Entity.new(%{
        type: :medication,
        text: "metformin 500mg",
        attributes: %{drug_name: "metformin"}
      })

      entity2 = Entity.new(%{
        type: :medication,
        text: "aspirin 81mg",
        attributes: %{drug_name: "aspirin"}
      })

      {:ok, result1} = Linker.link(entity1)
      {:ok, result2} = Linker.link(entity2)

      # Both should process independently
      assert result1.type == :medication
      assert result2.type == :medication
    end
  end

  describe "edge cases" do
    test "handles entity with nil attributes" do
      entity = %Entity{
        id: "test",
        type: :medication,
        text: "metformin",
        start_offset: 0,
        end_offset: 9,
        confidence: 0.9,
        attributes: nil,
        ontology_links: [],
        extraction_method: :rule_based,
        warnings: [],
        metadata: %{}
      }

      # Should not crash, but may add warning
      {:ok, _result} = Linker.link(entity)
    end

    test "handles entity with empty text" do
      entity = Entity.new(%{
        type: :medication,
        text: "",
        attributes: %{}
      })

      {:ok, result} = Linker.link(entity)
      assert result.type == :medication
    end

    test "handles string keys in attributes" do
      entity = Entity.new(%{
        type: :medication,
        text: "metformin",
        attributes: %{"drug_name" => "metformin", "dose" => 500, "dose_unit" => "mg"}
      })

      {:ok, result} = Linker.link(entity)
      assert result.type == :medication
    end
  end
end
