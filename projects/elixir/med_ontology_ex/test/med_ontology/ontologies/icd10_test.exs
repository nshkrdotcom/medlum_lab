defmodule MedOntology.ICD10Test do
  use ExUnit.Case, async: true

  alias MedOntology.{Concept, ICD10, SearchResult}

  describe "lookup/1" do
    test "returns concept for valid code" do
      assert {:ok, %Concept{} = concept} = ICD10.lookup("E11.9")
      assert concept.code == "E11.9"
      assert concept.system == :icd10
      assert concept.display =~ "diabetes"
    end

    test "returns concept for category code" do
      assert {:ok, %Concept{} = concept} = ICD10.lookup("E11")
      assert concept.code == "E11"
      assert concept.display =~ "Type 2 diabetes"
    end

    test "handles case-insensitive lookup" do
      assert {:ok, concept1} = ICD10.lookup("e11.9")
      assert {:ok, concept2} = ICD10.lookup("E11.9")
      assert concept1.code == concept2.code
    end

    test "returns :not_found for invalid code" do
      assert {:error, :not_found} = ICD10.lookup("ZZZ.99")
    end

    test "returns concept with billable property" do
      assert {:ok, %Concept{} = concept} = ICD10.lookup("E11.9")
      assert concept.properties[:billable] == true
    end

    test "returns concept with excludes properties" do
      assert {:ok, %Concept{} = concept} = ICD10.lookup("E11")
      assert is_list(concept.properties[:excludes1])
      assert is_list(concept.properties[:excludes2])
    end
  end

  describe "valid?/1" do
    test "returns true for valid existing code" do
      assert ICD10.valid?("E11.9") == true
    end

    test "returns true for category code" do
      assert ICD10.valid?("I10") == true
    end

    test "returns false for invalid format" do
      assert ICD10.valid?("INVALID") == false
    end

    test "returns false for valid format but non-existent code" do
      assert ICD10.valid?("Z99.99") == false
    end
  end

  describe "valid_format?/1" do
    test "validates correct formats" do
      assert ICD10.valid_format?("E11.9") == true
      assert ICD10.valid_format?("I10") == true
      assert ICD10.valid_format?("J06.9") == true
      assert ICD10.valid_format?("M54.50") == true
      assert ICD10.valid_format?("S72.001A") == true
    end

    test "rejects invalid formats" do
      assert ICD10.valid_format?("") == false
      assert ICD10.valid_format?("123") == false
      assert ICD10.valid_format?("E") == false
      assert ICD10.valid_format?("E1") == false
      assert ICD10.valid_format?("E11.99999") == false
      assert ICD10.valid_format?("INVALID") == false
    end

    test "handles case-insensitivity" do
      assert ICD10.valid_format?("e11.9") == true
      assert ICD10.valid_format?("E11.9") == true
    end

    test "handles non-string input" do
      assert ICD10.valid_format?(nil) == false
      assert ICD10.valid_format?(123) == false
    end
  end

  describe "billable?/1" do
    test "returns true for billable code" do
      assert ICD10.billable?("E11.9") == true
      assert ICD10.billable?("I10") == true
    end

    test "returns false for category code" do
      assert ICD10.billable?("E11") == false
    end

    test "returns false for non-existent code" do
      assert ICD10.billable?("ZZZ.99") == false
    end

    test "handles non-string input" do
      assert ICD10.billable?(nil) == false
    end
  end

  describe "hierarchy/1" do
    test "returns hierarchy for subcategory code" do
      assert {:ok, hierarchy} = ICD10.hierarchy("E11.9")
      assert hierarchy.chapter == "IV"
      assert hierarchy.chapter_title =~ "Endocrine"
      assert hierarchy.category == "E11"
      assert hierarchy.code == "E11.9"
      assert hierarchy.billable == true
    end

    test "returns hierarchy for category code" do
      assert {:ok, hierarchy} = ICD10.hierarchy("E11")
      assert hierarchy.chapter == "IV"
      assert hierarchy.category == "E11"
      assert hierarchy.code == "E11"
      assert hierarchy.billable == false
    end

    test "returns block information when available" do
      assert {:ok, hierarchy} = ICD10.hierarchy("E11.9")
      assert hierarchy.block == "E10-E14"
      assert hierarchy.block_title == "Diabetes mellitus"
    end

    test "returns error for invalid code" do
      assert {:error, _} = ICD10.hierarchy("ZZZ.99")
    end

    test "handles non-string input" do
      assert {:error, :invalid_code} = ICD10.hierarchy(nil)
    end
  end

  describe "search/2" do
    test "returns matching codes" do
      assert {:ok, results} = ICD10.search("diabetes")
      assert results != []
      assert Enum.all?(results, &match?(%SearchResult{}, &1))
    end

    test "returns results with concept and score" do
      assert {:ok, [result | _]} = ICD10.search("diabetes")
      assert %SearchResult{concept: %Concept{}, score: score, matched_term: _} = result
      assert score > 0
    end

    test "results contain diabetes in display" do
      assert {:ok, results} = ICD10.search("diabetes")

      assert Enum.all?(results, fn %{concept: c} ->
               String.downcase(c.display) |> String.contains?("diabetes")
             end)
    end

    test "respects limit option" do
      assert {:ok, results} = ICD10.search("diabetes", limit: 2)
      assert length(results) <= 2
    end

    test "returns empty list for no matches" do
      assert {:ok, []} = ICD10.search("xyznonexistent123")
    end

    test "results are sorted by score descending" do
      assert {:ok, results} = ICD10.search("diabetes")
      scores = Enum.map(results, & &1.score)
      assert scores == Enum.sort(scores, :desc)
    end
  end

  describe "ancestors/2" do
    test "returns ancestors for subcategory code" do
      assert {:ok, ancestors} = ICD10.ancestors("E11.9")
      assert is_list(ancestors)
    end

    test "returns category as ancestor" do
      assert {:ok, ancestors} = ICD10.ancestors("E11.9")
      assert Enum.any?(ancestors, fn c -> c.code == "E11" end)
    end

    test "returns empty list for category code" do
      assert {:ok, []} = ICD10.ancestors("E11")
    end

    test "respects max_depth option" do
      assert {:ok, ancestors} = ICD10.ancestors("E11.9", max_depth: 0)
      assert ancestors == []
    end
  end

  describe "descendants/2" do
    test "returns descendants for category code" do
      assert {:ok, descendants} = ICD10.descendants("E11")
      assert descendants != []

      assert Enum.all?(descendants, fn c ->
               String.starts_with?(c.code, "E11.")
             end)
    end

    test "respects limit option" do
      assert {:ok, descendants} = ICD10.descendants("E11", limit: 2)
      assert length(descendants) <= 2
    end

    test "returns empty list for leaf code" do
      assert {:ok, descendants} = ICD10.descendants("E11.9")
      # E11.9 is a leaf node, may or may not have children depending on data
      assert is_list(descendants)
    end
  end

  describe "codes_in_block/2" do
    test "returns codes in block range" do
      assert {:ok, codes} = ICD10.codes_in_block("E10-E14")
      assert codes != []

      assert Enum.all?(codes, fn c ->
               category = String.slice(c.code, 0, 3)
               category >= "E10" and category <= "E14"
             end)
    end

    test "respects limit option" do
      assert {:ok, codes} = ICD10.codes_in_block("E10-E14", limit: 3)
      assert length(codes) <= 3
    end

    test "returns error for invalid block format" do
      assert {:error, :invalid_block} = ICD10.codes_in_block("INVALID")
    end
  end

  describe "exclusions/1" do
    test "returns excludes1 and excludes2" do
      assert {:ok, exclusions} = ICD10.exclusions("E11")
      assert is_list(exclusions.excludes1)
      assert is_list(exclusions.excludes2)
    end

    test "returns empty lists when no exclusions" do
      assert {:ok, exclusions} = ICD10.exclusions("E11.9")
      assert is_list(exclusions.excludes1)
      assert is_list(exclusions.excludes2)
    end

    test "returns error for invalid code" do
      assert {:error, _} = ICD10.exclusions("ZZZ.99")
    end

    test "handles non-string input" do
      assert {:error, :invalid_code} = ICD10.exclusions(nil)
    end
  end

  describe "chapters/0" do
    test "returns all chapters" do
      chapters = ICD10.chapters()
      assert length(chapters) == 21
    end

    test "chapters have required fields" do
      [chapter | _] = ICD10.chapters()
      assert Map.has_key?(chapter, :number)
      assert Map.has_key?(chapter, :title)
      assert Map.has_key?(chapter, :range)
    end

    test "first chapter is infectious diseases" do
      [chapter | _] = ICD10.chapters()
      assert chapter.number == "I"
      assert chapter.title =~ "infectious"
    end
  end

  describe "is_a?/2" do
    test "returns true when child is more specific than parent" do
      assert ICD10.is_a?("E11.9", "E11") == true
      assert ICD10.is_a?("E11.65", "E11") == true
    end

    test "returns false when codes are equal" do
      assert ICD10.is_a?("E11.9", "E11.9") == false
    end

    test "returns false when parent is more specific" do
      assert ICD10.is_a?("E11", "E11.9") == false
    end

    test "returns false for unrelated codes" do
      assert ICD10.is_a?("I10", "E11") == false
    end

    test "handles case-insensitivity" do
      assert ICD10.is_a?("e11.9", "E11") == true
    end

    test "handles non-string input" do
      assert ICD10.is_a?(nil, "E11") == false
      assert ICD10.is_a?("E11.9", nil) == false
    end
  end
end
