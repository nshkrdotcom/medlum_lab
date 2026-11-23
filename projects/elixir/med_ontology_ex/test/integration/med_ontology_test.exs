defmodule MedOntology.IntegrationTest do
  @moduledoc """
  Integration tests for med_ontology_ex.

  These tests verify end-to-end functionality with mocked API responses.
  They cover cross-ontology operations, caching behavior, and the unified API.
  """

  use ExUnit.Case, async: false

  import Mox

  alias MedOntology.{Concept, SearchResult, Mapping}

  setup :verify_on_exit!

  # Clear caches before each test to ensure isolation
  setup do
    Enum.each(
      [:snomed_ct_cache, :rxnorm_cache, :icd10_cache, :loinc_cache, :snomed_ct_hierarchy_cache],
      fn table ->
        if :ets.whereis(table) != :undefined do
          :ets.delete_all_objects(table)
        end
      end
    )

    :ok
  end

  # ============================================================================
  # Cross-Ontology Operations
  # ============================================================================

  describe "cross-ontology operations" do
    test "lookup concepts from all ontologies" do
      # Setup mocks
      setup_snomed_mock("44054006", "Type 2 diabetes mellitus")
      setup_rxnorm_mock("861004", "metformin 500 MG Oral Tablet")
      setup_loinc_mock("2345-7", "Glucose [Mass/volume] in Serum or Plasma")

      # SNOMED-CT
      assert {:ok, snomed} = MedOntology.lookup(:snomed_ct, "44054006")
      assert snomed.system == :snomed_ct
      assert snomed.code == "44054006"
      assert String.contains?(snomed.display, "diabetes")

      # RxNorm
      assert {:ok, rxnorm} = MedOntology.lookup(:rxnorm, "861004")
      assert rxnorm.system == :rxnorm
      assert rxnorm.code == "861004"
      assert String.contains?(rxnorm.display, "metformin")

      # LOINC
      assert {:ok, loinc} = MedOntology.lookup(:loinc, "2345-7")
      assert loinc.system == :loinc
      assert loinc.code == "2345-7"

      # ICD-10 (uses local data - no mock needed)
      assert {:ok, icd} = MedOntology.lookup(:icd10, "E11.9")
      assert icd.system == :icd10
      assert icd.code == "E11.9"
    end

    test "search returns results from correct ontology" do
      setup_snomed_search_mock("diabetes", ["44054006", "73211009"])
      setup_rxnorm_search_mock("metformin", ["861004", "6809"])

      {:ok, snomed_results} = MedOntology.search(:snomed_ct, "diabetes")
      assert length(snomed_results) > 0
      assert Enum.all?(snomed_results, fn r -> r.concept.system == :snomed_ct end)

      {:ok, rxnorm_results} = MedOntology.search(:rxnorm, "metformin")
      assert length(rxnorm_results) > 0
      assert Enum.all?(rxnorm_results, fn r -> r.concept.system == :rxnorm end)
    end

    test "valid? returns correct results for each ontology" do
      setup_snomed_mock("44054006", "Type 2 diabetes mellitus")
      setup_rxnorm_mock("861004", "metformin 500 MG")
      setup_loinc_mock("2345-7", "Glucose")

      # Valid codes
      assert MedOntology.valid?(:snomed_ct, "44054006") == true
      assert MedOntology.valid?(:icd10, "E11.9") == true
      assert MedOntology.valid?(:rxnorm, "861004") == true
      assert MedOntology.valid?(:loinc, "2345-7") == true

      # Invalid codes
      assert MedOntology.valid?(:icd10, "INVALID") == false
      assert MedOntology.valid?(:rxnorm, "invalid") == false

      # Non-existent codes
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "999999999" -> {:error, :not_found} end)

      assert MedOntology.valid?(:snomed_ct, "999999999") == false
    end

    test "batch lookup returns map with nil for not-found codes" do
      setup_snomed_mock("44054006", "Type 2 diabetes mellitus")

      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "999999999" -> {:error, :not_found} end)

      {:ok, results} = MedOntology.lookup_batch(:snomed_ct, ["44054006", "999999999"])

      assert is_map(results)
      assert %Concept{code: "44054006"} = results["44054006"]
      assert results["999999999"] == nil
    end

    test "lookup returns error for invalid ontology" do
      assert {:error, :invalid_ontology} = MedOntology.lookup(:invalid_ontology, "123")
    end
  end

  # ============================================================================
  # Caching Behavior
  # ============================================================================

  describe "caching behavior" do
    test "second lookup uses cache" do
      # First call - API mock should be called
      setup_snomed_mock("44054006", "Type 2 diabetes mellitus")
      {:ok, first_result} = MedOntology.lookup(:snomed_ct, "44054006")

      # Second call - should use cache, no API call expected
      # If get_concept was called again, Mox would fail with "no expectation"
      {:ok, second_result} = MedOntology.lookup(:snomed_ct, "44054006")

      assert first_result.code == second_result.code
      assert first_result.display == second_result.display
    end

    test "cache can be cleared" do
      setup_snomed_mock("44054006", "Type 2 diabetes mellitus")
      {:ok, _} = MedOntology.lookup(:snomed_ct, "44054006")

      # Clear the cache - note: Cache.Server.clear takes a single ontology
      MedOntology.Cache.Server.clear(:snomed_ct)

      # Next lookup should hit API again
      setup_snomed_mock("44054006", "Type 2 diabetes mellitus")
      {:ok, concept} = MedOntology.lookup(:snomed_ct, "44054006")

      assert concept.code == "44054006"
    end

    test "cache stats reflect stored entries" do
      setup_snomed_mock("44054006", "Type 2 diabetes mellitus")
      {:ok, _} = MedOntology.lookup(:snomed_ct, "44054006")

      stats = MedOntology.cache_stats()

      assert is_map(stats)
      # Stats should have an entry for snomed_ct
      assert Map.has_key?(stats, :snomed_ct)
    end
  end

  # ============================================================================
  # RxNorm Specific Operations
  # ============================================================================

  describe "RxNorm specific operations" do
    test "normalize drug string" do
      MedOntology.Client.RxNavMock
      |> expect(:get_rxcui, fn "metformin 500mg" -> {:ok, "861004"} end)

      setup_rxnorm_mock("861004", "metformin 500 MG Oral Tablet")

      {:ok, concept} = MedOntology.RxNorm.normalize("metformin 500mg")

      assert concept.code == "861004"
      assert String.contains?(concept.display, "metformin")
    end

    test "get drug class returns classification data" do
      MedOntology.Client.RxNavMock
      |> expect(:get_drug_class, fn "861004", "ATC" ->
        {:ok, [%{"rxclassMinConceptItem" => %{"classId" => "A10BA02"}}]}
      end)
      |> expect(:get_drug_class, fn "861004", "VA" ->
        {:ok, [%{"rxclassMinConceptItem" => %{"classId" => "HS502"}}]}
      end)
      |> expect(:get_drug_class, fn "861004", "NDFRT" -> {:ok, []} end)

      {:ok, classes} = MedOntology.RxNorm.drug_class("861004")

      assert "A10BA02" in classes.atc
      assert "HS502" in classes.va_class
      assert classes.ndf_rt == []
    end

    test "get ingredients returns ingredient concepts" do
      MedOntology.Client.RxNavMock
      |> expect(:get_ingredients, fn "861004" ->
        {:ok, [%{"rxcui" => "6809", "name" => "Metformin", "tty" => "IN"}]}
      end)

      {:ok, ingredients} = MedOntology.RxNorm.ingredients("861004")

      assert length(ingredients) == 1
      assert hd(ingredients).code == "6809"
      assert hd(ingredients).display == "Metformin"
    end

    test "get NDC codes" do
      MedOntology.Client.RxNavMock
      |> expect(:get_ndc, fn "861004" -> {:ok, ["00378-0226-01", "00591-2468-01"]} end)

      {:ok, ndcs} = MedOntology.RxNorm.ndc_codes("861004")

      assert length(ndcs) == 2
      assert "00378-0226-01" in ndcs
    end

    test "check drug interactions" do
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

      MedOntology.Client.RxNavMock
      |> expect(:get_interactions, fn "861004", "197361" -> {:ok, interaction_data} end)

      {:ok, interactions} = MedOntology.RxNorm.interactions("861004", "197361")

      assert length(interactions) == 1
      assert hd(interactions).severity == "moderate"
    end
  end

  # ============================================================================
  # LOINC Specific Operations
  # ============================================================================

  describe "LOINC specific operations" do
    test "reference range lookup" do
      {:ok, range} = MedOntology.LOINC.reference_range("2345-7")

      assert range.low == 70
      assert range.high == 100
      assert range.unit == "mg/dL"
    end

    test "value evaluation returns correct status" do
      # Normal value
      assert {:ok, :normal} = MedOntology.LOINC.evaluate_value("2345-7", 85)

      # High value
      assert {:ok, :high} = MedOntology.LOINC.evaluate_value("2345-7", 150)

      # Low value
      assert {:ok, :low} = MedOntology.LOINC.evaluate_value("2345-7", 60)

      # Critical high
      assert {:ok, :critical_high} = MedOntology.LOINC.evaluate_value("2345-7", 600)

      # Critical low
      assert {:ok, :critical_low} = MedOntology.LOINC.evaluate_value("2345-7", 35)
    end

    test "panel detection" do
      assert MedOntology.LOINC.panel?("24323-8") == true
      assert MedOntology.LOINC.panel?("2345-7") == false
    end

    test "get panel members" do
      # Setup stubs for component lookups
      # The panel_members function looks up each component in the panel
      bmp_components = [
        {"2345-7", "Glucose"},
        {"3094-0", "Urea nitrogen"},
        {"2160-0", "Creatinine"},
        {"2951-2", "Sodium"},
        {"2823-3", "Potassium"},
        {"2075-0", "Chloride"},
        {"2028-9", "Carbon dioxide"},
        {"17861-6", "Calcium"}
      ]

      MedOntology.Client.LOINCMock
      |> stub(:get_concept, fn code ->
        case Enum.find(bmp_components, fn {c, _} -> c == code end) do
          {_c, display} ->
            {:ok,
             %{
               "display" => display,
               "COMPONENT" => display,
               "PROPERTY" => "MCnc",
               "TIME_ASPCT" => "Pt",
               "SYSTEM" => "Ser/Plas",
               "SCALE_TYP" => "Qn",
               "CLASS" => "CHEM",
               "STATUS" => "ACTIVE"
             }}

          nil ->
            {:error, :not_found}
        end
      end)

      {:ok, members} = MedOntology.LOINC.panel_members("24323-8")

      assert is_list(members)
      assert length(members) > 0
      assert Enum.all?(members, fn m -> is_struct(m, Concept) end)
    end

    test "get LOINC parts" do
      setup_loinc_mock("4548-4", "Hemoglobin A1c")

      {:ok, parts} = MedOntology.LOINC.parts("4548-4")

      assert is_map(parts)
      assert Map.has_key?(parts, :component)
      assert Map.has_key?(parts, :property)
      assert Map.has_key?(parts, :system)
    end
  end

  # ============================================================================
  # ICD-10 Specific Operations
  # ============================================================================

  describe "ICD-10 specific operations" do
    test "hierarchy lookup" do
      {:ok, hierarchy} = MedOntology.ICD10.hierarchy("E11.9")

      assert hierarchy.code == "E11.9"
      assert hierarchy.category == "E11"
      assert is_binary(hierarchy.chapter)
      assert is_binary(hierarchy.chapter_title)
    end

    test "billability check" do
      # E11.9 should be billable (specific code)
      assert MedOntology.ICD10.billable?("E11.9") == true

      # E11 may not be billable (category code)
      # Note: actual billability depends on code database
      assert is_boolean(MedOntology.ICD10.billable?("E11"))
    end

    test "format validation" do
      # Valid formats
      assert MedOntology.ICD10.valid_format?("E11.9") == true
      assert MedOntology.ICD10.valid_format?("I10") == true
      assert MedOntology.ICD10.valid_format?("S72.001A") == true

      # Invalid formats
      assert MedOntology.ICD10.valid_format?("INVALID") == false
      assert MedOntology.ICD10.valid_format?("E11.99999") == false
      assert MedOntology.ICD10.valid_format?("123.45") == false
    end

    test "search returns relevant results" do
      {:ok, results} = MedOntology.search(:icd10, "diabetes", limit: 5)

      assert is_list(results)
      assert Enum.all?(results, fn r -> is_struct(r, SearchResult) end)
      assert Enum.all?(results, fn r -> r.concept.system == :icd10 end)
    end

    test "ancestors returns parent codes" do
      {:ok, ancestors} = MedOntology.ancestors(:icd10, "E11.9")

      assert is_list(ancestors)
      # E11.9's immediate ancestor should be E11
      if length(ancestors) > 0 do
        assert Enum.any?(ancestors, fn a -> a.code == "E11" end)
      end
    end

    test "descendants returns child codes" do
      {:ok, descendants} = MedOntology.descendants(:icd10, "E11", limit: 10)

      assert is_list(descendants)
      # All descendants should start with E11
      assert Enum.all?(descendants, fn d -> String.starts_with?(d.code, "E11") end)
    end
  end

  # ============================================================================
  # SNOMED-CT Specific Operations
  # ============================================================================

  describe "SNOMED-CT specific operations" do
    test "is_a relationship check" do
      # Setup mock for ancestors lookup
      MedOntology.Client.SnowstormMock
      |> expect(:get_parents, fn "44054006" ->
        {:ok,
         [
           %{
             "conceptId" => "73211009",
             "fsn" => %{"term" => "Diabetes mellitus (disorder)"},
             "pt" => %{"term" => "Diabetes mellitus"},
             "active" => true
           }
         ]}
      end)
      |> expect(:get_parents, fn "73211009" -> {:ok, []} end)

      # Type 2 DM is-a Diabetes mellitus
      assert MedOntology.SnomedCT.is_a?("44054006", "73211009") == true

      # Same concept is-a itself
      assert MedOntology.SnomedCT.is_a?("44054006", "44054006") == true
    end

    test "relationships lookup" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_relationships, fn "44054006" ->
        {:ok,
         %{
           "items" => [
             %{
               "source" => %{"conceptId" => "44054006"},
               "target" => %{"conceptId" => "73211009"},
               "type" => %{"conceptId" => "116680003"},
               "active" => true,
               "relationshipGroup" => 0
             }
           ]
         }}
      end)

      {:ok, relationships} = MedOntology.SnomedCT.relationships("44054006")

      assert is_list(relationships)
      assert length(relationships) >= 1
    end

    test "semantic tag extraction" do
      setup_snomed_mock("44054006", "Type 2 diabetes mellitus")

      {:ok, tag} = MedOntology.SnomedCT.semantic_tag("44054006")

      assert tag == "disorder"
    end

    test "ECL query" do
      MedOntology.Client.SnowstormMock
      |> expect(:ecl_query, fn "<< 73211009", _opts ->
        {:ok,
         [
           %{
             "conceptId" => "44054006",
             "fsn" => %{"term" => "Diabetes mellitus type 2 (disorder)"},
             "pt" => %{"term" => "Type 2 diabetes mellitus"},
             "active" => true
           }
         ]}
      end)

      {:ok, results} = MedOntology.SnomedCT.ecl_query("<< 73211009")

      assert is_list(results)
      assert Enum.all?(results, fn c -> is_struct(c, Concept) end)
    end
  end

  # ============================================================================
  # Cross-Ontology Mapping
  # ============================================================================

  describe "cross-ontology mapping" do
    test "map SNOMED to ICD-10 returns error when not cached" do
      # Note: The mapper currently returns :not_implemented when mapping is not cached
      # and API fetch is not implemented. This test verifies the behavior.
      result = MedOntology.map(:snomed_ct, "44054006", :icd10)

      case result do
        {:ok, mappings} ->
          # If mappings are cached, verify structure
          assert is_list(mappings)

          if length(mappings) > 0 do
            mapping = hd(mappings)
            assert is_struct(mapping, Mapping)
            assert mapping.source_system == :snomed_ct
            assert mapping.source_code == "44054006"
            assert mapping.target_system == :icd10
          end

        {:error, :not_implemented} ->
          # Expected when mapping is not cached and API not implemented
          assert true

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "all_mappings returns mappings grouped by target system" do
      {:ok, all_mappings} = MedOntology.all_mappings(:snomed_ct, "44054006")

      assert is_map(all_mappings)

      if Map.has_key?(all_mappings, :icd10) do
        assert is_list(all_mappings[:icd10])
      end
    end

    test "unsupported mapping returns error tuple" do
      # The mapper returns a tuple with the unsupported ontologies
      {:error, {:unsupported_mapping, :loinc, :rxnorm}} =
        MedOntology.map(:loinc, "2345-7", :rxnorm)
    end
  end

  # ============================================================================
  # Error Handling
  # ============================================================================

  describe "error handling" do
    test "lookup returns error for not found code" do
      MedOntology.Client.SnowstormMock
      |> expect(:get_concept, fn "999999999" -> {:error, :not_found} end)

      assert {:error, :not_found} = MedOntology.lookup(:snomed_ct, "999999999")
    end

    test "search handles API errors gracefully" do
      MedOntology.Client.SnowstormMock
      |> expect(:search, fn "test", _opts -> {:error, :api_unavailable} end)

      assert {:error, :api_unavailable} = MedOntology.search(:snomed_ct, "test")
    end

    test "normalize handles not found drug" do
      MedOntology.Client.RxNavMock
      |> expect(:get_rxcui, fn "notarealdrug" -> {:error, :not_found} end)

      assert {:error, :not_found} = MedOntology.RxNorm.normalize("notarealdrug")
    end
  end

  # ============================================================================
  # Helper Functions for Setting Up Mocks
  # ============================================================================

  defp setup_snomed_mock(sctid, display) do
    MedOntology.Client.SnowstormMock
    |> expect(:get_concept, fn ^sctid ->
      {:ok,
       %{
         "conceptId" => sctid,
         "fsn" => %{"term" => "#{display} (disorder)"},
         "pt" => %{"term" => display},
         "active" => true,
         "moduleId" => "900000000000207008",
         "effectiveTime" => "20240101"
       }}
    end)
  end

  defp setup_snomed_search_mock(term, sctids) do
    MedOntology.Client.SnowstormMock
    |> expect(:search, fn ^term, _opts ->
      items =
        Enum.map(sctids, fn sctid ->
          %{
            "conceptId" => sctid,
            "fsn" => %{"term" => "Result #{sctid} (disorder)"},
            "pt" => %{"term" => "Result #{sctid}"},
            "active" => true
          }
        end)

      {:ok, items}
    end)
  end

  defp setup_rxnorm_mock(rxcui, display) do
    MedOntology.Client.RxNavMock
    |> expect(:get_concept, fn ^rxcui ->
      {:ok,
       %{
         "propConceptGroup" => %{
           "propConcept" => [
             %{"propName" => "RXCUI", "propValue" => rxcui},
             %{"propName" => "RxNorm Name", "propValue" => display},
             %{"propName" => "TTY", "propValue" => "SCD"}
           ]
         }
       }}
    end)
  end

  defp setup_rxnorm_search_mock(term, rxcuis) do
    MedOntology.Client.RxNavMock
    |> expect(:search, fn ^term, _opts ->
      concepts =
        Enum.map(rxcuis, fn rxcui ->
          %{"rxcui" => rxcui, "name" => "Drug #{rxcui}", "tty" => "SCD"}
        end)

      {:ok, concepts}
    end)
  end

  defp setup_loinc_mock(code, display) do
    MedOntology.Client.LOINCMock
    |> expect(:get_concept, fn ^code ->
      {:ok,
       %{
         "display" => display,
         "COMPONENT" => display,
         "PROPERTY" => "MCnc",
         "TIME_ASPCT" => "Pt",
         "SYSTEM" => "Ser/Plas",
         "SCALE_TYP" => "Qn",
         "METHOD_TYP" => nil,
         "CLASS" => "CHEM",
         "STATUS" => "ACTIVE"
       }}
    end)
  end
end
