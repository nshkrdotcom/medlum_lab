defmodule MedOntology.MappingTest do
  use ExUnit.Case, async: true

  alias MedOntology.Mapping

  describe "struct creation" do
    test "creates mapping with default values" do
      mapping = %Mapping{
        source_system: :snomed_ct,
        source_code: "44054006",
        target_system: :icd10,
        target_code: "E11.9"
      }

      assert mapping.source_system == :snomed_ct
      assert mapping.source_code == "44054006"
      assert mapping.target_system == :icd10
      assert mapping.target_code == "E11.9"
      assert mapping.equivalence == :related
      assert mapping.active == true
    end

    test "creates mapping with all fields" do
      mapping = %Mapping{
        source_system: :snomed_ct,
        source_code: "44054006",
        target_system: :icd10,
        target_code: "E11.9",
        equivalence: :equivalent,
        active: true
      }

      assert mapping.equivalence == :equivalent
      assert mapping.active == true
    end

    test "creates inactive mapping" do
      mapping = %Mapping{
        source_system: :snomed_ct,
        source_code: "12345",
        target_system: :icd10,
        target_code: "Z99.9",
        active: false
      }

      assert mapping.active == false
    end
  end

  describe "new/5" do
    test "creates mapping with minimal arguments" do
      mapping = Mapping.new(:snomed_ct, "44054006", :icd10, "E11.9")

      assert mapping.source_system == :snomed_ct
      assert mapping.source_code == "44054006"
      assert mapping.target_system == :icd10
      assert mapping.target_code == "E11.9"
      assert mapping.equivalence == :related
      assert mapping.active == true
    end

    test "creates mapping with all options" do
      mapping = Mapping.new(:snomed_ct, "44054006", :icd10, "E11.9",
        equivalence: :equivalent,
        active: false
      )

      assert mapping.equivalence == :equivalent
      assert mapping.active == false
    end
  end

  describe "equivalence types" do
    test "supports equivalent type" do
      mapping = %Mapping{
        source_system: :snomed_ct,
        source_code: "1",
        target_system: :icd10,
        target_code: "2",
        equivalence: :equivalent
      }

      assert mapping.equivalence == :equivalent
    end

    test "supports narrower type" do
      mapping = %Mapping{
        source_system: :snomed_ct,
        source_code: "1",
        target_system: :icd10,
        target_code: "2",
        equivalence: :narrower
      }

      assert mapping.equivalence == :narrower
    end

    test "supports broader type" do
      mapping = %Mapping{
        source_system: :snomed_ct,
        source_code: "1",
        target_system: :icd10,
        target_code: "2",
        equivalence: :broader
      }

      assert mapping.equivalence == :broader
    end

    test "supports related type" do
      mapping = %Mapping{
        source_system: :snomed_ct,
        source_code: "1",
        target_system: :icd10,
        target_code: "2",
        equivalence: :related
      }

      assert mapping.equivalence == :related
    end
  end
end
