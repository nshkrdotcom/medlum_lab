defmodule ClinicalNerEx.EntityTest do
  use ExUnit.Case, async: true

  alias ClinicalNerEx.Entity

  doctest ClinicalNerEx.Entity

  describe "Entity struct" do
    test "creates entity with default values" do
      entity = %Entity{
        type: :medication,
        text: "metformin 500mg",
        start_offset: 0,
        end_offset: 15,
        confidence: 0.95
      }

      assert entity.type == :medication
      assert entity.text == "metformin 500mg"
      assert entity.start_offset == 0
      assert entity.end_offset == 15
      assert entity.confidence == 0.95
      assert entity.attributes == %{}
      assert entity.ontology_links == []
      assert entity.extraction_method == :rule_based
      assert entity.warnings == []
      assert entity.metadata == %{}
    end

    test "creates entity with all fields" do
      entity = %Entity{
        id: "test-id",
        type: :lab_value,
        text: "A1c 6.5%",
        start_offset: 10,
        end_offset: 18,
        confidence: 0.92,
        attributes: %{lab_name: "A1c", value: 6.5, unit: "%"},
        ontology_links: [%{system: :loinc, code: "4548-4", display: "HbA1c", confidence: 0.9}],
        extraction_method: :transformer,
        warnings: ["May need review"],
        metadata: %{source: "test"}
      }

      assert entity.id == "test-id"
      assert entity.type == :lab_value
      assert entity.attributes.lab_name == "A1c"
      assert length(entity.ontology_links) == 1
      assert entity.extraction_method == :transformer
      assert entity.warnings == ["May need review"]
      assert entity.metadata.source == "test"
    end
  end

  describe "new/1" do
    test "generates unique ID" do
      entity1 = Entity.new(%{type: :medication, text: "test"})
      entity2 = Entity.new(%{type: :medication, text: "test"})

      assert entity1.id != entity2.id
      assert is_binary(entity1.id)
      assert String.length(entity1.id) == 16
    end

    test "preserves provided attributes" do
      entity =
        Entity.new(%{
          type: :diagnosis,
          text: "diabetes",
          confidence: 0.88,
          attributes: %{condition: "type 2 diabetes"}
        })

      assert entity.type == :diagnosis
      assert entity.text == "diabetes"
      assert entity.confidence == 0.88
      assert entity.attributes.condition == "type 2 diabetes"
    end

    test "sets default values when not provided" do
      entity = Entity.new(%{type: :medication, text: "aspirin"})

      assert entity.attributes == %{}
      assert entity.ontology_links == []
      assert entity.extraction_method == :rule_based
      assert entity.warnings == []
      assert entity.metadata == %{}
    end
  end

  describe "overlaps?/2" do
    test "detects overlapping spans" do
      e1 = %Entity{start_offset: 0, end_offset: 10, type: :medication, text: "a"}
      e2 = %Entity{start_offset: 5, end_offset: 15, type: :diagnosis, text: "b"}

      assert Entity.overlaps?(e1, e2)
      assert Entity.overlaps?(e2, e1)
    end

    test "returns false for non-overlapping spans" do
      e1 = %Entity{start_offset: 0, end_offset: 10, type: :medication, text: "a"}
      e2 = %Entity{start_offset: 15, end_offset: 25, type: :diagnosis, text: "b"}

      refute Entity.overlaps?(e1, e2)
      refute Entity.overlaps?(e2, e1)
    end

    test "returns false for adjacent spans" do
      e1 = %Entity{start_offset: 0, end_offset: 10, type: :medication, text: "a"}
      e2 = %Entity{start_offset: 10, end_offset: 20, type: :diagnosis, text: "b"}

      refute Entity.overlaps?(e1, e2)
    end

    test "detects overlap when one is contained in the other" do
      e1 = %Entity{start_offset: 0, end_offset: 20, type: :medication, text: "a"}
      e2 = %Entity{start_offset: 5, end_offset: 15, type: :diagnosis, text: "b"}

      assert Entity.overlaps?(e1, e2)
      assert Entity.overlaps?(e2, e1)
    end

    test "detects overlap for identical spans" do
      e1 = %Entity{start_offset: 5, end_offset: 15, type: :medication, text: "a"}
      e2 = %Entity{start_offset: 5, end_offset: 15, type: :diagnosis, text: "b"}

      assert Entity.overlaps?(e1, e2)
    end
  end

  describe "contains?/2" do
    test "detects contained spans" do
      outer = %Entity{start_offset: 0, end_offset: 20, type: :medication, text: "a"}
      inner = %Entity{start_offset: 5, end_offset: 15, type: :diagnosis, text: "b"}

      assert Entity.contains?(outer, inner)
      refute Entity.contains?(inner, outer)
    end

    test "returns true for identical spans" do
      e1 = %Entity{start_offset: 5, end_offset: 15, type: :medication, text: "a"}
      e2 = %Entity{start_offset: 5, end_offset: 15, type: :diagnosis, text: "b"}

      assert Entity.contains?(e1, e2)
      assert Entity.contains?(e2, e1)
    end

    test "returns false for partially overlapping spans" do
      e1 = %Entity{start_offset: 0, end_offset: 10, type: :medication, text: "a"}
      e2 = %Entity{start_offset: 5, end_offset: 15, type: :diagnosis, text: "b"}

      refute Entity.contains?(e1, e2)
      refute Entity.contains?(e2, e1)
    end

    test "returns false for non-overlapping spans" do
      e1 = %Entity{start_offset: 0, end_offset: 10, type: :medication, text: "a"}
      e2 = %Entity{start_offset: 15, end_offset: 25, type: :diagnosis, text: "b"}

      refute Entity.contains?(e1, e2)
    end
  end

  describe "span_length/1" do
    test "calculates span length" do
      entity = %Entity{start_offset: 5, end_offset: 20, type: :medication, text: "a"}
      assert Entity.span_length(entity) == 15
    end

    test "returns zero for empty span" do
      entity = %Entity{start_offset: 10, end_offset: 10, type: :medication, text: ""}
      assert Entity.span_length(entity) == 0
    end
  end

  describe "valid_types/0" do
    test "returns all valid entity types" do
      types = Entity.valid_types()

      assert :medication in types
      assert :lab_value in types
      assert :diagnosis in types
      assert :procedure in types
      assert :temporal in types
      assert :finding in types
      assert length(types) == 6
    end
  end

  describe "valid_type?/1" do
    test "returns true for valid types" do
      assert Entity.valid_type?(:medication)
      assert Entity.valid_type?(:lab_value)
      assert Entity.valid_type?(:diagnosis)
      assert Entity.valid_type?(:procedure)
      assert Entity.valid_type?(:temporal)
      assert Entity.valid_type?(:finding)
    end

    test "returns false for invalid types" do
      refute Entity.valid_type?(:invalid)
      refute Entity.valid_type?(:unknown)
      refute Entity.valid_type?("medication")
      refute Entity.valid_type?(nil)
    end
  end
end
