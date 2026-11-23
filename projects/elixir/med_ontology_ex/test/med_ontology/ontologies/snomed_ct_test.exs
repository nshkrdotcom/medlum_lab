defmodule MedOntology.SnomedCTTest do
  # Note: async: false because tests share the ETS cache tables
  use ExUnit.Case, async: false

  import Mox

  alias MedOntology.Concept
  alias MedOntology.SearchResult
  alias MedOntology.SnomedCT

  setup :verify_on_exit!

  # Clear cache before each test to ensure isolation
  setup do
    # Clear the SNOMED-CT cache tables
    if :ets.whereis(:snomed_ct_cache) != :undefined do
      :ets.delete_all_objects(:snomed_ct_cache)
    end

    if :ets.whereis(:snomed_ct_hierarchy_cache) != :undefined do
      :ets.delete_all_objects(:snomed_ct_hierarchy_cache)
    end

    :ok
  end

  @diabetes_data %{
    "conceptId" => "44054006",
    "fsn" => %{"term" => "Diabetes mellitus type 2 (disorder)"},
    "pt" => %{"term" => "Type 2 diabetes mellitus"},
    "active" => true,
    "moduleId" => "900000000000207008",
    "definitionStatus" => "FULLY_DEFINED",
    "effectiveTime" => "20020131"
  }

  @diabetes_parent_data %{
    "conceptId" => "73211009",
    "fsn" => %{"term" => "Diabetes mellitus (disorder)"},
    "pt" => %{"term" => "Diabetes mellitus"},
    "active" => true,
    "moduleId" => "900000000000207008",
    "definitionStatus" => "FULLY_DEFINED"
  }

  @inactive_concept_data %{
    "conceptId" => "12345",
    "fsn" => %{"term" => "Inactive concept (disorder)"},
    "pt" => %{"term" => "Inactive concept"},
    "active" => false,
    "moduleId" => "900000000000207008",
    "definitionStatus" => "FULLY_DEFINED"
  }

  describe "lookup/1" do
    test "returns concept for valid SCTID" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "44054006" -> {:ok, @diabetes_data} end)

      assert {:ok, %Concept{} = concept} = SnomedCT.lookup("44054006")
      assert concept.code == "44054006"
      assert concept.system == :snomed_ct
      assert concept.display == "Type 2 diabetes mellitus"
      assert concept.fully_specified_name == "Diabetes mellitus type 2 (disorder)"
      assert "disorder" in concept.semantic_types
      assert concept.active == true
    end

    test "returns :not_found for invalid SCTID" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "invalid" -> {:error, :not_found} end)

      assert {:error, :not_found} = SnomedCT.lookup("invalid")
    end

    test "returns cached concept on second lookup" do
      # First lookup - fetches from API
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "44054006" -> {:ok, @diabetes_data} end)

      assert {:ok, _} = SnomedCT.lookup("44054006")

      # Second lookup - should use cache (no API call expected)
      assert {:ok, %Concept{code: "44054006"}} = SnomedCT.lookup("44054006")
    end

    test "includes relationships when option is set" do
      relationships_data = %{
        "items" => [
          %{
            "source" => %{"conceptId" => "44054006"},
            "target" => %{"conceptId" => "73211009"},
            "type" => %{"conceptId" => "116680003"},
            "active" => true,
            "relationshipGroup" => 0
          }
        ]
      }

      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "44054006" -> {:ok, @diabetes_data} end)
      |> expect(:get_relationships, fn "44054006" -> {:ok, relationships_data} end)

      assert {:ok, %Concept{} = concept} = SnomedCT.lookup("44054006", include_relationships: true)
      assert Map.has_key?(concept.properties, :relationships)
      assert length(concept.properties.relationships) == 1
    end
  end

  describe "search/2" do
    test "returns search results sorted by score" do
      search_results = [
        %{
          "conceptId" => "44054006",
          "fsn" => %{"term" => "Diabetes mellitus type 2 (disorder)"},
          "pt" => %{"term" => "Type 2 diabetes mellitus"},
          "active" => true
        },
        %{
          "conceptId" => "73211009",
          "fsn" => %{"term" => "Diabetes mellitus (disorder)"},
          "pt" => %{"term" => "Diabetes mellitus"},
          "active" => true
        }
      ]

      MedOntology.Client.SnowstormMock
      |> expect(:search, fn "diabetes", _opts -> {:ok, search_results} end)

      assert {:ok, results} = SnomedCT.search("diabetes")
      assert length(results) == 2
      assert %SearchResult{} = hd(results)
      # "Diabetes mellitus" should have higher score (more exact match)
      assert hd(results).concept.display == "Diabetes mellitus"
    end

    test "passes options to client" do
      MedOntology.Client.SnowstormMock
      |> expect(:search, fn "diabetes", opts ->
        assert Keyword.get(opts, :limit) == 10
        assert Keyword.get(opts, :semantic_tags) == ["disorder"]
        {:ok, []}
      end)

      assert {:ok, []} = SnomedCT.search("diabetes", limit: 10, semantic_types: ["disorder"])
    end

    test "returns empty list when no results found" do
      MedOntology.Client.SnowstormMock
      |> expect(:search, fn "xyz123abc", _opts -> {:ok, []} end)

      assert {:ok, []} = SnomedCT.search("xyz123abc")
    end
  end

  describe "valid?/1" do
    test "returns true for active concept" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "44054006" -> {:ok, @diabetes_data} end)

      assert SnomedCT.valid?("44054006") == true
    end

    test "returns false for inactive concept" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "12345" -> {:ok, @inactive_concept_data} end)

      assert SnomedCT.valid?("12345") == false
    end

    test "returns false for non-existent concept" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "invalid" -> {:error, :not_found} end)

      assert SnomedCT.valid?("invalid") == false
    end
  end

  describe "semantic_tag/1" do
    test "extracts semantic tag from FSN" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "44054006" -> {:ok, @diabetes_data} end)

      assert {:ok, "disorder"} = SnomedCT.semantic_tag("44054006")
    end

    test "returns nil when FSN has no semantic tag" do
      data = %{
        "conceptId" => "99999",
        "fsn" => %{"term" => "No semantic tag"},
        "pt" => %{"term" => "No semantic tag"},
        "active" => true,
        "moduleId" => "900000000000207008",
        "definitionStatus" => "FULLY_DEFINED"
      }

      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "99999" -> {:ok, data} end)

      assert {:ok, nil} = SnomedCT.semantic_tag("99999")
    end
  end

  describe "ancestors/2" do
    test "returns parent concepts" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_parents, fn "44054006" -> {:ok, [@diabetes_parent_data]} end)
      |> expect(:get_parents, fn "73211009" -> {:ok, []} end)

      assert {:ok, ancestors} = SnomedCT.ancestors("44054006")
      assert length(ancestors) == 1
      assert hd(ancestors).code == "73211009"
      assert hd(ancestors).display == "Diabetes mellitus"
    end

    test "respects max_depth option" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_parents, fn "44054006" -> {:ok, [@diabetes_parent_data]} end)

      # With max_depth: 1, should stop after first level
      assert {:ok, ancestors} = SnomedCT.ancestors("44054006", max_depth: 1)
      assert length(ancestors) == 1
    end

    test "returns empty list when no parents" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_parents, fn "138875005" -> {:ok, []} end)

      assert {:ok, []} = SnomedCT.ancestors("138875005")
    end
  end

  describe "descendants/2" do
    test "returns child concepts" do
      children = [
        %{
          "conceptId" => "44054006",
          "fsn" => %{"term" => "Diabetes mellitus type 2 (disorder)"},
          "pt" => %{"term" => "Type 2 diabetes mellitus"},
          "active" => true
        }
      ]

      MedOntology.Client.SnowstormMock
      |> expect(:get_children, fn "73211009", _opts -> {:ok, children} end)

      assert {:ok, descendants} = SnomedCT.descendants("73211009")
      assert length(descendants) == 1
      assert hd(descendants).code == "44054006"
    end

    test "returns empty list when no children" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_children, fn "44054006", _opts -> {:ok, []} end)

      assert {:ok, []} = SnomedCT.descendants("44054006")
    end
  end

  describe "is_a?/2" do
    test "returns true when child is descendant of parent" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_parents, fn "44054006" -> {:ok, [@diabetes_parent_data]} end)
      |> expect(:get_parents, fn "73211009" -> {:ok, []} end)

      assert SnomedCT.is_a?("44054006", "73211009") == true
    end

    test "returns true when concept is same as parent" do
      # Same concept should return true without API call
      assert SnomedCT.is_a?("44054006", "44054006") == true
    end

    test "returns false when child is not descendant of parent" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_parents, fn "44054006" -> {:ok, [@diabetes_parent_data]} end)
      |> expect(:get_parents, fn "73211009" -> {:ok, []} end)

      # 22298006 is Myocardial infarction, not in diabetes hierarchy
      assert SnomedCT.is_a?("44054006", "22298006") == false
    end
  end

  describe "relationships/1" do
    test "returns relationships for concept" do
      relationships_data = %{
        "items" => [
          %{
            "source" => %{"conceptId" => "44054006"},
            "target" => %{"conceptId" => "73211009"},
            "type" => %{"conceptId" => "116680003"},
            "active" => true,
            "relationshipGroup" => 0
          },
          %{
            "source" => %{"conceptId" => "44054006"},
            "target" => %{"conceptId" => "181277001"},
            "type" => %{"conceptId" => "363698007"},
            "active" => true,
            "relationshipGroup" => 1
          }
        ]
      }

      MedOntology.Client.SnowstormMock
      |> expect(:get_relationships, fn "44054006" -> {:ok, relationships_data} end)

      assert {:ok, rels} = SnomedCT.relationships("44054006")
      assert length(rels) == 2

      is_a_rel = Enum.find(rels, &(&1.type == :is_a))
      assert is_a_rel.source_code == "44054006"
      assert is_a_rel.target_code == "73211009"

      finding_site_rel = Enum.find(rels, &(&1.type == :finding_site))
      assert finding_site_rel.target_code == "181277001"
    end

    test "returns empty list when no relationships" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_relationships, fn "44054006" -> {:ok, %{"items" => []}} end)

      assert {:ok, []} = SnomedCT.relationships("44054006")
    end
  end

  describe "ecl_query/2" do
    test "executes ECL query and returns concepts" do
      ecl_results = [
        %{
          "conceptId" => "44054006",
          "fsn" => %{"term" => "Diabetes mellitus type 2 (disorder)"},
          "pt" => %{"term" => "Type 2 diabetes mellitus"},
          "active" => true
        },
        %{
          "conceptId" => "46635009",
          "fsn" => %{"term" => "Diabetes mellitus type 1 (disorder)"},
          "pt" => %{"term" => "Type 1 diabetes mellitus"},
          "active" => true
        }
      ]

      MedOntology.Client.SnowstormMock
      |> expect(:ecl_query, fn "<< 73211009", _opts -> {:ok, ecl_results} end)

      assert {:ok, concepts} = SnomedCT.ecl_query("<< 73211009")
      assert length(concepts) == 2
      assert Enum.all?(concepts, &(&1.system == :snomed_ct))
    end

    test "passes limit option to client" do
      MedOntology.Client.SnowstormMock
      |> expect(:ecl_query, fn "<< 73211009", opts ->
        assert Keyword.get(opts, :limit) == 50
        {:ok, []}
      end)

      assert {:ok, []} = SnomedCT.ecl_query("<< 73211009", limit: 50)
    end
  end
end
