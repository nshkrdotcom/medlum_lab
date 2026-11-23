defmodule MedOntology.SearchResultTest do
  use ExUnit.Case, async: true

  alias MedOntology.{Concept, SearchResult}

  describe "struct creation" do
    test "creates search result with all fields" do
      concept = %Concept{
        code: "44054006",
        system: :snomed_ct,
        display: "Type 2 diabetes mellitus"
      }

      result = %SearchResult{
        concept: concept,
        score: 0.95,
        matched_term: "Type 2 diabetes mellitus"
      }

      assert result.concept == concept
      assert result.score == 0.95
      assert result.matched_term == "Type 2 diabetes mellitus"
    end
  end

  describe "new/3" do
    test "creates search result with new/3" do
      concept = Concept.new("44054006", :snomed_ct, "Type 2 diabetes mellitus")
      result = SearchResult.new(concept, 0.95, "Type 2 diabetes mellitus")

      assert result.concept == concept
      assert result.score == 0.95
      assert result.matched_term == "Type 2 diabetes mellitus"
    end

    test "creates search result with different scores" do
      concept = Concept.new("12345", :icd10, "Test")

      result1 = SearchResult.new(concept, 1.0, "Test")
      result2 = SearchResult.new(concept, 0.5, "Test")
      result3 = SearchResult.new(concept, 0.0, "Test")

      assert result1.score == 1.0
      assert result2.score == 0.5
      assert result3.score == 0.0
    end

    test "creates search result with partial match" do
      concept = Concept.new("44054006", :snomed_ct, "Type 2 diabetes mellitus")
      result = SearchResult.new(concept, 0.75, "diabetes")

      assert result.matched_term == "diabetes"
      assert result.score == 0.75
    end
  end
end
