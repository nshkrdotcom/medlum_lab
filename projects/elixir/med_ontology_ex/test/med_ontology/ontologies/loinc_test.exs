defmodule MedOntology.LOINCTest do
  # Note: async: false because tests share the ETS cache tables
  use ExUnit.Case, async: false

  import Mox

  alias MedOntology.Concept
  alias MedOntology.LOINC
  alias MedOntology.LOINC.{Panels, ReferenceRanges}
  alias MedOntology.SearchResult

  setup :verify_on_exit!

  # Clear cache before each test to ensure isolation
  setup do
    if :ets.whereis(:loinc_cache) != :undefined do
      :ets.delete_all_objects(:loinc_cache)
    end

    :ok
  end

  @glucose_data %{
    "display" => "Glucose [Mass/volume] in Serum or Plasma",
    "COMPONENT" => "Glucose",
    "PROPERTY" => "MCnc",
    "TIME_ASPCT" => "Pt",
    "SYSTEM" => "Ser/Plas",
    "SCALE_TYP" => "Qn",
    "CLASS" => "CHEM"
  }

  describe "lookup/1" do
    test "returns concept for valid LOINC code" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "2345-7" -> {:ok, @glucose_data} end)

      assert {:ok, %Concept{} = concept} = LOINC.lookup("2345-7")
      assert concept.code == "2345-7"
      assert concept.system == :loinc
      assert concept.display =~ "Glucose"
    end

    test "includes LOINC parts in properties" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "2345-7" -> {:ok, @glucose_data} end)

      assert {:ok, %Concept{} = concept} = LOINC.lookup("2345-7")
      assert concept.properties[:component] == "Glucose"
      assert concept.properties[:property] == "MCnc"
      assert concept.properties[:system] == "Ser/Plas"
      assert concept.properties[:scale_type] == "Qn"
    end

    test "returns :not_found for invalid code" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "invalid" -> {:error, :not_found} end)

      assert {:error, :not_found} = LOINC.lookup("invalid")
    end

    test "returns cached concept on second lookup" do
      # First lookup - fetches from API
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "2345-7" -> {:ok, @glucose_data} end)

      assert {:ok, _} = LOINC.lookup("2345-7")

      # Second lookup - should use cache (no API call expected)
      assert {:ok, %Concept{code: "2345-7"}} = LOINC.lookup("2345-7")
    end

    test "includes semantic types from CLASS" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "2345-7" -> {:ok, @glucose_data} end)

      assert {:ok, %Concept{} = concept} = LOINC.lookup("2345-7")
      assert "CHEM" in concept.semantic_types
    end
  end

  describe "search/2" do
    test "returns search results sorted by score" do
      search_results = [
        %{"code" => "718-7", "display" => "Hemoglobin [Mass/volume] in Blood"},
        %{"code" => "4548-4", "display" => "Hemoglobin A1c/Hemoglobin.total in Blood"}
      ]

      MedOntology.Client.LOINCMock
      |> expect(:search, fn "hemoglobin", _opts -> {:ok, search_results} end)

      assert {:ok, results} = LOINC.search("hemoglobin")
      assert length(results) == 2
      assert %SearchResult{} = hd(results)
      # "Hemoglobin" should have higher score (more exact match)
      assert hd(results).concept.display =~ "Hemoglobin"
    end

    test "respects limit option" do
      search_results = [
        %{"code" => "718-7", "display" => "Hemoglobin"},
        %{"code" => "4544-3", "display" => "Hematocrit"},
        %{"code" => "777-3", "display" => "Platelets"}
      ]

      MedOntology.Client.LOINCMock
      |> expect(:search, fn "blood", _opts -> {:ok, search_results} end)

      assert {:ok, results} = LOINC.search("blood", limit: 2)
      assert length(results) == 2
    end

    test "returns empty list when no results found" do
      MedOntology.Client.LOINCMock
      |> expect(:search, fn "xyz123abc", _opts -> {:ok, []} end)

      assert {:ok, []} = LOINC.search("xyz123abc")
    end
  end

  describe "valid?/1" do
    test "returns false for invalid format" do
      # No API call expected for invalid format
      assert LOINC.valid?("invalid") == false
      assert LOINC.valid?("ABCD-X") == false
      assert LOINC.valid?("1234") == false
    end

    test "returns true for valid existing code" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "2345-7" -> {:ok, @glucose_data} end)

      assert LOINC.valid?("2345-7") == true
    end

    test "returns false for valid format but non-existent code" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "9999-9" -> {:error, :not_found} end)

      assert LOINC.valid?("9999-9") == false
    end
  end

  describe "parts/1" do
    test "returns LOINC parts" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "2345-7" -> {:ok, @glucose_data} end)

      assert {:ok, parts} = LOINC.parts("2345-7")
      assert parts.component == "Glucose"
      assert parts.property == "MCnc"
      assert parts.time_aspect == "Pt"
      assert parts.system == "Ser/Plas"
      assert parts.scale_type == "Qn"
    end

    test "returns error for invalid code" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "invalid" -> {:error, :not_found} end)

      assert {:error, :not_found} = LOINC.parts("invalid")
    end
  end

  describe "reference_range/1" do
    test "returns reference range for common code" do
      assert {:ok, range} = LOINC.reference_range("2345-7")
      assert range.name == "Glucose"
      assert range.low == 70
      assert range.high == 100
      assert range.unit == "mg/dL"
    end

    test "returns reference range with critical values" do
      assert {:ok, range} = LOINC.reference_range("2345-7")
      assert range.critical_low == 40
      assert range.critical_high == 500
    end

    test "returns :not_available for unknown code" do
      assert {:error, :not_available} = LOINC.reference_range("unknown-code")
    end
  end

  describe "evaluate_value/2" do
    test "returns :normal for value in range" do
      assert {:ok, :normal} = LOINC.evaluate_value("2345-7", 85)
    end

    test "returns :high for elevated value" do
      assert {:ok, :high} = LOINC.evaluate_value("2345-7", 150)
    end

    test "returns :low for decreased value" do
      assert {:ok, :low} = LOINC.evaluate_value("2345-7", 60)
    end

    test "returns :critical_high for critically elevated value" do
      assert {:ok, :critical_high} = LOINC.evaluate_value("2345-7", 600)
    end

    test "returns :critical_low for critically decreased value" do
      assert {:ok, :critical_low} = LOINC.evaluate_value("2345-7", 35)
    end

    test "returns :not_available for unknown code" do
      assert {:error, :not_available} = LOINC.evaluate_value("unknown", 100)
    end
  end

  describe "by_component/2" do
    test "searches by component name" do
      search_results = [
        %{"code" => "718-7", "display" => "Hemoglobin [Mass/volume] in Blood"}
      ]

      MedOntology.Client.LOINCMock
      |> expect(:search, fn "hemoglobin", _opts -> {:ok, search_results} end)

      assert {:ok, [%SearchResult{} | _]} = LOINC.by_component("hemoglobin")
    end
  end

  describe "panel_members/1" do
    test "returns members for known panel from local definitions" do
      MedOntology.Client.LOINCMock
      |> stub(:get_concept, fn code ->
        case code do
          "2345-7" -> {:ok, @glucose_data}
          _ -> {:ok, %{"display" => "Test #{code}"}}
        end
      end)

      assert {:ok, members} = LOINC.panel_members("24323-8")
      assert members != []
      assert Enum.all?(members, fn m -> m.system == :loinc end)
    end

    test "falls back to API for unknown panel" do
      api_members = [
        %{"code" => "1234-5", "display" => "Test Component 1"},
        %{"code" => "2345-6", "display" => "Test Component 2"}
      ]

      MedOntology.Client.LOINCMock
      |> expect(:get_panel_members, fn "99999-9" -> {:ok, api_members} end)

      assert {:ok, [_member1, _member2]} = LOINC.panel_members("99999-9")
    end

    test "returns error for non-existent panel" do
      MedOntology.Client.LOINCMock
      |> expect(:get_panel_members, fn "invalid" -> {:error, :not_found} end)

      assert {:error, :not_found} = LOINC.panel_members("invalid")
    end
  end

  describe "panel?/1" do
    test "returns true for known panel codes" do
      assert LOINC.panel?("24323-8") == true
      assert LOINC.panel?("24325-3") == true
      assert LOINC.panel?("58410-2") == true
    end

    test "returns false for non-panel codes" do
      assert LOINC.panel?("2345-7") == false
    end
  end

  describe "panel_info/1" do
    test "returns panel information" do
      assert {:ok, panel} = LOINC.panel_info("24323-8")
      assert panel.name == "Basic Metabolic Panel (BMP)"
      assert is_list(panel.components)
      assert "2345-7" in panel.components
    end

    test "returns error for non-existent panel" do
      assert {:error, :not_found} = LOINC.panel_info("unknown")
    end
  end

  describe "class/1" do
    test "returns class for valid code" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "2345-7" -> {:ok, @glucose_data} end)

      assert {:ok, "CHEM"} = LOINC.class("2345-7")
    end

    test "returns error for invalid code" do
      MedOntology.Client.LOINCMock
      |> expect(:get_concept, fn "invalid" -> {:error, :not_found} end)

      assert {:error, :not_found} = LOINC.class("invalid")
    end
  end

  describe "panels_with_component/1" do
    test "finds panels containing glucose" do
      panels = LOINC.panels_with_component("2345-7")
      assert panels != []
      assert {"24323-8", "Basic Metabolic Panel (BMP)"} in panels
      assert {"24325-3", "Comprehensive Metabolic Panel (CMP)"} in panels
    end

    test "returns empty list for component not in any panel" do
      panels = LOINC.panels_with_component("nonexistent-code")
      assert panels == []
    end
  end

  describe "ancestors/1 and descendants/1" do
    test "ancestors returns empty list (LOINC has no hierarchy)" do
      assert {:ok, []} = LOINC.ancestors("2345-7")
    end

    test "descendants returns empty list (LOINC has no hierarchy)" do
      assert {:ok, []} = LOINC.descendants("2345-7")
    end
  end

  # Tests for submodules

  describe "ReferenceRanges" do
    test "all/0 returns all reference ranges" do
      ranges = ReferenceRanges.all()
      assert is_map(ranges)
      assert Map.has_key?(ranges, "2345-7")
      assert Map.has_key?(ranges, "4548-4")
    end

    test "available_codes/0 returns list of codes" do
      codes = ReferenceRanges.available_codes()
      assert is_list(codes)
      assert "2345-7" in codes
    end

    test "available?/1 checks if code has reference range" do
      assert ReferenceRanges.available?("2345-7") == true
      assert ReferenceRanges.available?("unknown") == false
    end

    test "by_category/1 returns ranges for category" do
      electrolytes = ReferenceRanges.by_category(:electrolytes)
      assert Map.has_key?(electrolytes, "2951-2")
      assert Map.has_key?(electrolytes, "2823-3")
    end
  end

  describe "Panels" do
    test "all/0 returns all panels" do
      panels = Panels.all()
      assert is_map(panels)
      assert Map.has_key?(panels, "24323-8")
    end

    test "available_panels/0 returns list of panel codes" do
      codes = Panels.available_panels()
      assert is_list(codes)
      assert "24323-8" in codes
      assert "57021-8" in codes
    end

    test "components/1 returns component codes" do
      assert {:ok, components} = Panels.components("57021-8")
      assert "2093-3" in components
      assert "2085-9" in components
    end

    test "name/1 returns panel name" do
      assert {:ok, "Lipid Panel"} = Panels.name("57021-8")
    end

    test "description/1 returns panel description" do
      assert {:ok, description} = Panels.description("57021-8")
      assert description =~ "Lipid"
    end

    test "by_category/1 returns panel codes for category" do
      assert ["24323-8", "24325-3"] = Panels.by_category(:metabolic)
      assert ["58410-2"] = Panels.by_category(:hematology)
    end
  end
end
