defmodule MedOntology.RxNormTest do
  # Note: async: false because tests share the ETS cache tables
  use ExUnit.Case, async: false

  import Mox

  alias MedOntology.Concept
  alias MedOntology.RxNorm
  alias MedOntology.SearchResult

  setup :verify_on_exit!

  # Clear cache before each test to ensure isolation
  setup do
    if :ets.whereis(:rxnorm_cache) != :undefined do
      :ets.delete_all_objects(:rxnorm_cache)
    end

    :ok
  end

  @metformin_props %{
    "propConceptGroup" => %{
      "propConcept" => [
        %{"propName" => "RXCUI", "propValue" => "861004"},
        %{"propName" => "RxNorm Name", "propValue" => "metformin hydrochloride 500 MG Oral Tablet"},
        %{"propName" => "TTY", "propValue" => "SCD"},
        %{"propName" => "RxNorm Synonym", "propValue" => "metformin 500mg tablet"},
        %{"propName" => "RXAUI", "propValue" => "1234567"},
        %{"propName" => "SUPPRESS", "propValue" => "N"},
        %{"propName" => "LANGUAGE", "propValue" => "ENG"}
      ]
    }
  }

  @metformin_ingredient %{
    "rxcui" => "6809",
    "name" => "Metformin",
    "tty" => "IN"
  }

  describe "lookup/1" do
    test "returns concept for valid RxCUI" do
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "861004" -> {:ok, @metformin_props} end)

      assert {:ok, %Concept{} = concept} = RxNorm.lookup("861004")
      assert concept.code == "861004"
      assert concept.system == :rxnorm
      assert concept.display == "metformin hydrochloride 500 MG Oral Tablet"
      assert "SCD" in concept.semantic_types
      assert concept.active == true
    end

    test "returns :not_found for invalid RxCUI" do
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "invalid" -> {:error, :not_found} end)

      assert {:error, :not_found} = RxNorm.lookup("invalid")
    end

    test "returns cached concept on second lookup" do
      # First lookup - fetches from API
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "861004" -> {:ok, @metformin_props} end)

      assert {:ok, _} = RxNorm.lookup("861004")

      # Second lookup - should use cache (no API call expected)
      assert {:ok, %Concept{code: "861004"}} = RxNorm.lookup("861004")
    end

    test "includes ingredients when include_relationships option is set" do
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "861004" -> {:ok, @metformin_props} end)
      |> expect(:get_ingredients, fn "861004" -> {:ok, [@metformin_ingredient]} end)

      assert {:ok, %Concept{} = concept} = RxNorm.lookup("861004", include_relationships: true)
      assert Map.has_key?(concept.properties, :ingredients)
      assert length(concept.properties.ingredients) == 1
      assert hd(concept.properties.ingredients).display == "Metformin"
    end
  end

  describe "search/2" do
    test "returns search results sorted by score" do
      search_results = [
        %{"rxcui" => "861004", "name" => "metformin hydrochloride 500 MG Oral Tablet", "tty" => "SCD"},
        %{"rxcui" => "6809", "name" => "Metformin", "tty" => "IN"}
      ]

      MedOntology.Client.RxNavMock
      |> expect(:search, fn "metformin", _opts -> {:ok, search_results} end)

      assert {:ok, results} = RxNorm.search("metformin")
      assert length(results) == 2
      assert %SearchResult{} = hd(results)
      # "Metformin" should have higher score (more exact match)
      assert hd(results).concept.display == "Metformin"
    end

    test "respects limit option" do
      search_results = [
        %{"rxcui" => "861004", "name" => "metformin 500 MG", "tty" => "SCD"},
        %{"rxcui" => "861005", "name" => "metformin 850 MG", "tty" => "SCD"},
        %{"rxcui" => "861006", "name" => "metformin 1000 MG", "tty" => "SCD"}
      ]

      MedOntology.Client.RxNavMock
      |> expect(:search, fn "metformin", _opts -> {:ok, search_results} end)

      assert {:ok, results} = RxNorm.search("metformin", limit: 2)
      assert length(results) == 2
    end

    test "returns empty list when no results found" do
      MedOntology.Client.RxNavMock
      |> expect(:search, fn "xyz123abc", _opts -> {:ok, []} end)

      assert {:ok, []} = RxNorm.search("xyz123abc")
    end
  end

  describe "valid?/1" do
    test "returns true for valid numeric RxCUI" do
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "861004" -> {:ok, @metformin_props} end)

      assert RxNorm.valid?("861004") == true
    end

    test "returns false for non-numeric code" do
      # No API call expected for invalid format
      assert RxNorm.valid?("invalid") == false
    end

    test "returns false for non-existent RxCUI" do
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "999999999" -> {:error, :not_found} end)

      assert RxNorm.valid?("999999999") == false
    end
  end

  describe "normalize/1" do
    test "normalizes drug string to RxNorm concept" do
      MedOntology.Client.RxNavMock
      |> expect(:get_rxcui, fn "metformin 500mg" -> {:ok, "861004"} end)
      |> expect(:get_concept, fn "861004" -> {:ok, @metformin_props} end)

      assert {:ok, %Concept{code: "861004"}} = RxNorm.normalize("metformin 500mg")
    end

    test "returns :not_found for unknown drug" do
      MedOntology.Client.RxNavMock
      |> expect(:get_rxcui, fn "unknown drug xyz" -> {:error, :not_found} end)

      assert {:error, :not_found} = RxNorm.normalize("unknown drug xyz")
    end

    test "caches normalized results" do
      MedOntology.Client.RxNavMock
      |> expect(:get_rxcui, fn "metformin 500mg" -> {:ok, "861004"} end)
      |> expect(:get_concept, fn "861004" -> {:ok, @metformin_props} end)

      # First call
      assert {:ok, %Concept{}} = RxNorm.normalize("metformin 500mg")

      # Second call should use cache (no additional API calls expected)
      assert {:ok, %Concept{code: "861004"}} = RxNorm.normalize("metformin 500mg")
    end
  end

  describe "ingredients/1" do
    test "returns ingredient concepts" do
      MedOntology.Client.RxNavMock
      |> expect(:get_ingredients, fn "861004" -> {:ok, [@metformin_ingredient]} end)

      assert {:ok, [%Concept{code: "6809", display: "Metformin"}]} = RxNorm.ingredients("861004")
    end

    test "returns empty list when no ingredients" do
      MedOntology.Client.RxNavMock
      |> expect(:get_ingredients, fn "6809" -> {:ok, []} end)

      assert {:ok, []} = RxNorm.ingredients("6809")
    end

    test "caches ingredient results" do
      MedOntology.Client.RxNavMock
      |> expect(:get_ingredients, fn "861004" -> {:ok, [@metformin_ingredient]} end)

      # First call
      assert {:ok, _} = RxNorm.ingredients("861004")

      # Second call should use cache
      assert {:ok, [%Concept{code: "6809"}]} = RxNorm.ingredients("861004")
    end
  end

  describe "drug_class/1" do
    test "returns drug classifications" do
      atc_classes = [
        %{"rxclassMinConceptItem" => %{"classId" => "A10BA02", "className" => "Metformin"}}
      ]

      va_classes = [
        %{"rxclassMinConceptItem" => %{"classId" => "HS502", "className" => "Blood Glucose Regulators"}}
      ]

      MedOntology.Client.RxNavMock
      |> expect(:get_drug_class, fn "861004", "ATC" -> {:ok, atc_classes} end)
      |> expect(:get_drug_class, fn "861004", "VA" -> {:ok, va_classes} end)
      |> expect(:get_drug_class, fn "861004", "NDFRT" -> {:ok, []} end)

      assert {:ok, classes} = RxNorm.drug_class("861004")
      assert "A10BA02" in classes.atc
      assert "HS502" in classes.va_class
      assert classes.ndf_rt == []
    end

    test "handles missing classifications gracefully" do
      MedOntology.Client.RxNavMock
      |> expect(:get_drug_class, fn "861004", "ATC" -> {:error, :not_found} end)
      |> expect(:get_drug_class, fn "861004", "VA" -> {:error, :not_found} end)
      |> expect(:get_drug_class, fn "861004", "NDFRT" -> {:error, :not_found} end)

      assert {:ok, classes} = RxNorm.drug_class("861004")
      assert classes.atc == []
      assert classes.va_class == []
      assert classes.ndf_rt == []
    end
  end

  describe "ndc_codes/1" do
    test "returns NDC codes" do
      ndcs = ["00378-0226-01", "00591-2468-01"]

      MedOntology.Client.RxNavMock
      |> expect(:get_ndc, fn "861004" -> {:ok, ndcs} end)

      assert {:ok, ^ndcs} = RxNorm.ndc_codes("861004")
    end

    test "returns empty list when no NDC codes" do
      MedOntology.Client.RxNavMock
      |> expect(:get_ndc, fn "6809" -> {:ok, []} end)

      assert {:ok, []} = RxNorm.ndc_codes("6809")
    end
  end

  describe "interactions/2" do
    test "returns drug interactions" do
      interaction_data = [
        %{
          "fullInteractionType" => [
            %{
              "interactionPair" => [
                %{
                  "severity" => "moderate",
                  "description" => "May increase risk of lactic acidosis"
                }
              ]
            }
          ]
        }
      ]

      MedOntology.Client.RxNavMock
      |> expect(:get_interactions, fn "861004", "197361" -> {:ok, interaction_data} end)

      assert {:ok, interactions} = RxNorm.interactions("861004", "197361")
      assert length(interactions) == 1
      assert hd(interactions).severity == "moderate"
    end

    test "returns empty list when no interactions" do
      MedOntology.Client.RxNavMock
      |> expect(:get_interactions, fn "861004", "197361" -> {:ok, []} end)

      assert {:ok, []} = RxNorm.interactions("861004", "197361")
    end

    test "normalizes cache key order" do
      interaction_data = [
        %{
          "fullInteractionType" => [
            %{
              "interactionPair" => [
                %{"severity" => "moderate", "description" => "Test interaction"}
              ]
            }
          ]
        }
      ]

      # First call with one order
      MedOntology.Client.RxNavMock
      |> expect(:get_interactions, fn "197361", "861004" -> {:ok, interaction_data} end)

      assert {:ok, _} = RxNorm.interactions("197361", "861004")

      # Second call with reversed order should use cache (no API call)
      assert {:ok, interactions} = RxNorm.interactions("861004", "197361")
      assert length(interactions) == 1
    end
  end

  describe "ancestors/1" do
    test "returns ingredient concepts as ancestors" do
      MedOntology.Client.RxNavMock
      |> expect(:get_ingredients, fn "861004" -> {:ok, [@metformin_ingredient]} end)

      assert {:ok, ancestors} = RxNorm.ancestors("861004")
      assert length(ancestors) == 1
      assert hd(ancestors).code == "6809"
    end
  end

  describe "descendants/1" do
    test "returns empty list (RxNorm is ingredient-based)" do
      # No API call expected
      assert {:ok, []} = RxNorm.descendants("6809")
    end
  end

  describe "dose_form/1" do
    test "extracts dose form from concept name" do
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "861004" -> {:ok, @metformin_props} end)

      assert {:ok, "Oral Tablet"} = RxNorm.dose_form("861004")
    end
  end

  describe "strength/1" do
    test "extracts strength from concept name" do
      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "861004" -> {:ok, @metformin_props} end)

      assert {:ok, %{value: "500", unit: "MG"}} = RxNorm.strength("861004")
    end

    test "returns nil values when strength not found" do
      concept_without_strength = %{
        "propConceptGroup" => %{
          "propConcept" => [
            %{"propName" => "RXCUI", "propValue" => "6809"},
            %{"propName" => "RxNorm Name", "propValue" => "Metformin"},
            %{"propName" => "TTY", "propValue" => "IN"}
          ]
        }
      }

      MedOntology.Client.RxNavMock
      |> expect(:get_concept, fn "6809" -> {:ok, concept_without_strength} end)

      assert {:ok, %{value: nil, unit: nil}} = RxNorm.strength("6809")
    end
  end
end
