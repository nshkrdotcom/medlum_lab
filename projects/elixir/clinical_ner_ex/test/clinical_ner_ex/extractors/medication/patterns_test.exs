defmodule ClinicalNerEx.Extractors.Medication.PatternsTest do
  use ExUnit.Case, async: true

  alias ClinicalNerEx.Extractors.Medication.Patterns

  describe "full_pattern/0" do
    test "returns a compiled regex" do
      pattern = Patterns.full_pattern()
      assert %Regex{} = pattern
    end

    test "matches full medication specification" do
      pattern = Patterns.full_pattern()
      assert Regex.match?(pattern, "metformin 500mg PO BID")
      assert Regex.match?(pattern, "lisinopril 10 mg po daily")
    end
  end

  describe "simple_pattern/0" do
    test "returns a compiled regex" do
      pattern = Patterns.simple_pattern()
      assert %Regex{} = pattern
    end

    test "matches drug + dose + unit" do
      pattern = Patterns.simple_pattern()
      assert Regex.match?(pattern, "aspirin 81mg")
      assert Regex.match?(pattern, "metformin 500 mg")
    end
  end

  describe "frequency_map/0" do
    test "returns frequency normalization map" do
      map = Patterns.frequency_map()
      assert is_map(map)
      assert map["bid"] == "BID"
      assert map["BID"] == "BID"
      assert map["daily"] == "daily"
    end
  end

  describe "route_map/0" do
    test "returns route normalization map" do
      map = Patterns.route_map()
      assert is_map(map)
      assert map["po"] == "PO"
      assert map["PO"] == "PO"
      assert map["iv"] == "IV"
      assert map["sc"] == "SC"
    end
  end

  describe "extract/1 offset handling" do
    test "returns correct start offset for medication at beginning" do
      text = "metformin 500mg"
      [{start, _end, _match}] = Patterns.extract(text)
      assert start == 0
    end

    test "returns correct start offset for medication in middle" do
      text = "Patient takes metformin 500mg daily"
      results = Patterns.extract(text)
      assert length(results) >= 1

      [{start, _end, match}] = results
      assert start > 0
      assert match["drug_name"] == "metformin"
    end

    test "returns correct end offset" do
      text = "metformin 500mg"
      [{start, end_offset, _match}] = Patterns.extract(text)
      extracted = String.slice(text, start, end_offset - start)
      assert extracted =~ ~r/metformin 500\s*mg/i
    end
  end

  describe "unit variations" do
    test "extracts mg" do
      [{_, _, match}] = Patterns.extract("test 100mg")
      assert match["dose_unit"] == "mg"
    end

    test "extracts mcg" do
      [{_, _, match}] = Patterns.extract("test 200mcg")
      assert match["dose_unit"] == "mcg"
    end

    test "extracts g" do
      [{_, _, match}] = Patterns.extract("test 1g")
      assert match["dose_unit"] == "g"
    end

    test "extracts mL" do
      [{_, _, match}] = Patterns.extract("test 15mL")
      assert match["dose_unit"] =~ ~r/mL|ml/
    end

    test "extracts units" do
      [{_, _, match}] = Patterns.extract("insulin 10units")
      assert match["dose_unit"] =~ ~r/units?/
    end

    test "extracts IU" do
      [{_, _, match}] = Patterns.extract("vitamin 1000IU")
      assert match["dose_unit"] == "IU"
    end
  end

  describe "route variations" do
    test "extracts PO route" do
      [{_, _, match}] = Patterns.extract("test 100mg PO")
      assert match["route"] =~ ~r/PO|po/
    end

    test "extracts IV route" do
      [{_, _, match}] = Patterns.extract("test 100mg IV")
      assert match["route"] =~ ~r/IV|iv/
    end

    test "extracts SC route" do
      [{_, _, match}] = Patterns.extract("test 100mg SC")
      assert match["route"] =~ ~r/SC|sc/
    end

    test "extracts IM route" do
      [{_, _, match}] = Patterns.extract("test 100mg IM")
      assert match["route"] =~ ~r/IM|im/
    end

    test "extracts SL route" do
      [{_, _, match}] = Patterns.extract("test 100mg SL")
      assert match["route"] =~ ~r/SL|sl/
    end

    test "extracts topical route" do
      [{_, _, match}] = Patterns.extract("test 100mg topical")
      assert match["route"] =~ ~r/topical/i
    end

    test "extracts inhaled route" do
      [{_, _, match}] = Patterns.extract("test 100mcg inhaled")
      assert match["route"] =~ ~r/inhaled/i
    end
  end

  describe "frequency variations" do
    test "extracts BID" do
      [{_, _, match}] = Patterns.extract("test 100mg PO BID")
      assert match["frequency"] =~ ~r/BID|bid/
    end

    test "extracts TID" do
      [{_, _, match}] = Patterns.extract("test 100mg TID")
      assert match["frequency"] =~ ~r/TID|tid/
    end

    test "extracts QID" do
      [{_, _, match}] = Patterns.extract("test 100mg QID")
      assert match["frequency"] =~ ~r/QID|qid/
    end

    test "extracts daily" do
      [{_, _, match}] = Patterns.extract("test 100mg daily")
      assert match["frequency"] =~ ~r/daily/i
    end

    test "extracts q8h" do
      [{_, _, match}] = Patterns.extract("test 100mg q8h")
      assert match["frequency"] =~ ~r/q\d+h/
    end

    test "extracts qhs (at bedtime)" do
      [{_, _, match}] = Patterns.extract("test 100mg qhs")
      assert match["frequency"] =~ ~r/qhs/i
    end
  end

  describe "parse_match/1 normalization" do
    test "normalizes drug name with leading/trailing whitespace" do
      match = %{"drug_name" => "  metformin  ", "dose" => "500", "dose_unit" => "mg"}
      attrs = Patterns.parse_match(match)
      assert attrs.drug_name == "metformin"
    end

    test "normalizes empty strings to nil" do
      match = %{"drug_name" => "test", "dose" => "", "dose_unit" => ""}
      attrs = Patterns.parse_match(match)
      assert attrs.dose == nil
      assert attrs.dose_unit == nil
    end

    test "parses integer dose string" do
      match = %{"drug_name" => "test", "dose" => "500", "dose_unit" => "mg"}
      attrs = Patterns.parse_match(match)
      assert attrs.dose == 500.0
    end

    test "parses float dose string" do
      match = %{"drug_name" => "test", "dose" => "0.125", "dose_unit" => "mg"}
      attrs = Patterns.parse_match(match)
      assert attrs.dose == 0.125
    end

    test "normalizes unit to units" do
      match = %{"drug_name" => "test", "dose" => "10", "dose_unit" => "unit"}
      attrs = Patterns.parse_match(match)
      assert attrs.dose_unit == "units"
    end

    test "sets default prn to false" do
      match = %{"drug_name" => "test", "dose" => "10", "dose_unit" => "mg"}
      attrs = Patterns.parse_match(match)
      assert attrs.prn == false
    end
  end

  describe "prn?/1" do
    test "case insensitive PRN detection" do
      assert Patterns.prn?("PRN")
      assert Patterns.prn?("prn")
      assert Patterns.prn?("Prn")
    end

    test "detects PRN in context" do
      assert Patterns.prn?("take medication PRN for pain")
      assert Patterns.prn?("PRN medication for headache")
    end

    test "detects as needed variations" do
      assert Patterns.prn?("take as needed")
      assert Patterns.prn?("AS NEEDED for pain")
    end
  end

  describe "extract_duration/1" do
    test "singular vs plural days" do
      assert Patterns.extract_duration("for 1 day") == "1 days"
      assert Patterns.extract_duration("for 7 days") == "7 days"
    end

    test "singular vs plural weeks" do
      assert Patterns.extract_duration("for 1 week") == "1 weeks"
      assert Patterns.extract_duration("for 2 weeks") == "2 weeks"
    end

    test "with 'for' prefix" do
      assert Patterns.extract_duration("for 10 days") == "10 days"
    end

    test "with 'x' prefix" do
      assert Patterns.extract_duration("x 5 days") == "5 days"
    end

    test "case insensitive" do
      assert Patterns.extract_duration("for 7 Days") == "7 days"
      assert Patterns.extract_duration("for 2 WEEKS") == "2 weeks"
    end
  end
end
