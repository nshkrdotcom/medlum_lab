defmodule MedOntology.ConceptTest do
  use ExUnit.Case, async: true

  alias MedOntology.Concept

  describe "struct creation" do
    test "creates concept with default values" do
      concept = %Concept{code: "12345", system: :snomed_ct, display: "Test"}

      assert concept.code == "12345"
      assert concept.system == :snomed_ct
      assert concept.display == "Test"
      assert concept.synonyms == []
      assert concept.active == true
      assert concept.semantic_types == []
      assert concept.properties == %{}
      assert concept.fully_specified_name == nil
      assert concept.effective_time == nil
    end

    test "creates concept with all fields" do
      concept = %Concept{
        code: "44054006",
        system: :snomed_ct,
        display: "Type 2 diabetes mellitus",
        fully_specified_name: "Diabetes mellitus type 2 (disorder)",
        synonyms: ["T2DM", "NIDDM"],
        active: true,
        semantic_types: ["disorder"],
        properties: %{module_id: "900000000000207008"},
        effective_time: ~D[2024-01-01]
      }

      assert concept.code == "44054006"
      assert concept.system == :snomed_ct
      assert concept.display == "Type 2 diabetes mellitus"
      assert concept.fully_specified_name == "Diabetes mellitus type 2 (disorder)"
      assert concept.synonyms == ["T2DM", "NIDDM"]
      assert concept.active == true
      assert concept.semantic_types == ["disorder"]
      assert concept.properties == %{module_id: "900000000000207008"}
      assert concept.effective_time == ~D[2024-01-01]
    end

    test "creates concept with inactive status" do
      concept = %Concept{
        code: "12345",
        system: :snomed_ct,
        display: "Retired concept",
        active: false
      }

      assert concept.active == false
    end
  end

  describe "new/4" do
    test "creates concept with minimal arguments" do
      concept = Concept.new("44054006", :snomed_ct, "Type 2 diabetes mellitus")

      assert concept.code == "44054006"
      assert concept.system == :snomed_ct
      assert concept.display == "Type 2 diabetes mellitus"
      assert concept.active == true
      assert concept.synonyms == []
    end

    test "creates concept with all options" do
      concept =
        Concept.new("44054006", :snomed_ct, "Type 2 diabetes mellitus",
          fully_specified_name: "Diabetes mellitus type 2 (disorder)",
          synonyms: ["T2DM"],
          active: true,
          semantic_types: ["disorder"],
          properties: %{extra: "data"},
          effective_time: ~D[2024-01-01]
        )

      assert concept.fully_specified_name == "Diabetes mellitus type 2 (disorder)"
      assert concept.synonyms == ["T2DM"]
      assert concept.semantic_types == ["disorder"]
      assert concept.properties == %{extra: "data"}
      assert concept.effective_time == ~D[2024-01-01]
    end
  end

  describe "ontology types" do
    test "supports snomed_ct system" do
      concept = %Concept{code: "44054006", system: :snomed_ct, display: "Test"}
      assert concept.system == :snomed_ct
    end

    test "supports icd10 system" do
      concept = %Concept{code: "E11.9", system: :icd10, display: "Test"}
      assert concept.system == :icd10
    end

    test "supports rxnorm system" do
      concept = %Concept{code: "861004", system: :rxnorm, display: "Test"}
      assert concept.system == :rxnorm
    end

    test "supports loinc system" do
      concept = %Concept{code: "2345-7", system: :loinc, display: "Test"}
      assert concept.system == :loinc
    end
  end
end
