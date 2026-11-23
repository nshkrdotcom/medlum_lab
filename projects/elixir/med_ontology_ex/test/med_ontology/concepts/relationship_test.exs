defmodule MedOntology.RelationshipTest do
  use ExUnit.Case, async: true

  alias MedOntology.Relationship

  describe "struct creation" do
    test "creates relationship with default values" do
      relationship = %Relationship{
        source_code: "44054006",
        target_code: "73211009",
        type: :is_a
      }

      assert relationship.source_code == "44054006"
      assert relationship.target_code == "73211009"
      assert relationship.type == :is_a
      assert relationship.active == true
      assert relationship.group == nil
    end

    test "creates relationship with all fields" do
      relationship = %Relationship{
        source_code: "44054006",
        target_code: "73211009",
        type: :is_a,
        active: true,
        group: 1
      }

      assert relationship.source_code == "44054006"
      assert relationship.target_code == "73211009"
      assert relationship.type == :is_a
      assert relationship.active == true
      assert relationship.group == 1
    end

    test "creates inactive relationship" do
      relationship = %Relationship{
        source_code: "12345",
        target_code: "67890",
        type: :finding_site,
        active: false
      }

      assert relationship.active == false
    end
  end

  describe "new/4" do
    test "creates relationship with minimal arguments" do
      relationship = Relationship.new("44054006", "73211009", :is_a)

      assert relationship.source_code == "44054006"
      assert relationship.target_code == "73211009"
      assert relationship.type == :is_a
      assert relationship.active == true
      assert relationship.group == nil
    end

    test "creates relationship with all options" do
      relationship = Relationship.new("44054006", "73211009", :is_a, active: false, group: 2)

      assert relationship.active == false
      assert relationship.group == 2
    end
  end

  describe "relationship types" do
    test "supports is_a relationship" do
      rel = %Relationship{source_code: "1", target_code: "2", type: :is_a}
      assert rel.type == :is_a
    end

    test "supports part_of relationship" do
      rel = %Relationship{source_code: "1", target_code: "2", type: :part_of}
      assert rel.type == :part_of
    end

    test "supports has_ingredient relationship" do
      rel = %Relationship{source_code: "1", target_code: "2", type: :has_ingredient}
      assert rel.type == :has_ingredient
    end

    test "supports finding_site relationship" do
      rel = %Relationship{source_code: "1", target_code: "2", type: :finding_site}
      assert rel.type == :finding_site
    end

    test "supports associated_morphology relationship" do
      rel = %Relationship{source_code: "1", target_code: "2", type: :associated_morphology}
      assert rel.type == :associated_morphology
    end
  end
end
