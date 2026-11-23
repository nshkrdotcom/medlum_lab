defmodule ClinicalNerEx.Extractors.MedicationTest do
  use ExUnit.Case, async: true

  alias ClinicalNerEx.Extractors.Medication
  alias ClinicalNerEx.Extractors.Medication.Patterns

  describe "Patterns.extract/1" do
    test "extracts drug with dose and unit" do
      text = "metformin 500 mg"
      results = Patterns.extract(text)

      assert length(results) == 1
      {start, end_offset, match} = hd(results)
      assert start == 0
      assert end_offset == 16
      assert match["drug_name"] == "metformin"
      assert match["dose"] == "500"
      assert match["dose_unit"] == "mg"
    end

    test "extracts drug with full specification" do
      text = "lisinopril 10mg PO daily"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match} = hd(results)
      assert match["drug_name"] =~ ~r/lisinopril/i
      assert match["dose"] == "10"
      assert match["dose_unit"] == "mg"
      assert match["route"] =~ ~r/PO|po/
      assert match["frequency"] =~ ~r/daily/
    end

    test "extracts drug with BID frequency" do
      text = "metformin 500mg BID"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match} = hd(results)
      assert match["drug_name"] == "metformin"
      assert match["frequency"] =~ ~r/BID|bid/
    end

    test "extracts multiple medications" do
      text = "Patient on metformin 500mg BID and lisinopril 10mg daily"
      results = Patterns.extract(text)

      assert length(results) >= 2
      drug_names = Enum.map(results, fn {_, _, m} -> m["drug_name"] end) |> Enum.map(&String.downcase/1)
      assert "metformin" in drug_names
      assert "lisinopril" in drug_names
    end

    test "extracts decimal doses" do
      text = "levothyroxine 0.05mg daily"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match} = hd(results)
      assert match["dose"] == "0.05"
    end

    test "extracts insulin with units" do
      text = "insulin 20 units SC"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match} = hd(results)
      assert match["dose"] == "20"
      assert match["dose_unit"] == "units"
      assert match["route"] =~ ~r/SC|sc/
    end

    test "extracts medication with IV route" do
      text = "vancomycin 1g IV q12h"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match} = hd(results)
      assert match["drug_name"] == "vancomycin"
      assert match["dose"] == "1"
      assert match["dose_unit"] == "g"
      assert match["route"] =~ ~r/IV|iv/
    end

    test "returns empty list for no medications" do
      text = "Patient denies any medications"
      results = Patterns.extract(text)
      assert results == []
    end

    test "extracts medications with mL unit" do
      text = "lactulose 30mL PO TID"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match} = hd(results)
      assert match["dose"] == "30"
      assert match["dose_unit"] =~ ~r/mL|ml/
    end
  end

  describe "Patterns.parse_match/1" do
    test "normalizes drug name to lowercase" do
      match = %{"drug_name" => "MetFORMIN", "dose" => "500", "dose_unit" => "mg"}
      attrs = Patterns.parse_match(match)

      assert attrs.drug_name == "metformin"
    end

    test "parses dose to float" do
      match = %{"drug_name" => "test", "dose" => "500", "dose_unit" => "mg"}
      attrs = Patterns.parse_match(match)

      assert attrs.dose == 500.0
    end

    test "parses decimal dose" do
      match = %{"drug_name" => "test", "dose" => "0.125", "dose_unit" => "mg"}
      attrs = Patterns.parse_match(match)

      assert attrs.dose == 0.125
    end

    test "normalizes mL unit" do
      match = %{"drug_name" => "test", "dose" => "10", "dose_unit" => "ml"}
      attrs = Patterns.parse_match(match)

      assert attrs.dose_unit == "mL"
    end

    test "normalizes IU unit" do
      match = %{"drug_name" => "test", "dose" => "100", "dose_unit" => "iu"}
      attrs = Patterns.parse_match(match)

      assert attrs.dose_unit == "IU"
    end

    test "normalizes route to uppercase" do
      match = %{"drug_name" => "test", "dose" => "10", "dose_unit" => "mg", "route" => "po"}
      attrs = Patterns.parse_match(match)

      assert attrs.route == "PO"
    end

    test "normalizes frequency" do
      match = %{"drug_name" => "test", "dose" => "10", "dose_unit" => "mg", "frequency" => "bid"}
      attrs = Patterns.parse_match(match)

      assert attrs.frequency == "BID"
    end

    test "handles nil values" do
      match = %{"drug_name" => "test", "dose" => nil, "dose_unit" => nil}
      attrs = Patterns.parse_match(match)

      assert attrs.drug_name == "test"
      assert attrs.dose == nil
      assert attrs.dose_unit == nil
    end
  end

  describe "Patterns.prn?/1" do
    test "detects PRN" do
      assert Patterns.prn?("tylenol 500mg PRN for pain")
      assert Patterns.prn?("ibuprofen 400mg prn")
    end

    test "detects 'as needed'" do
      assert Patterns.prn?("ibuprofen 400mg as needed")
      assert Patterns.prn?("tylenol as needed for pain")
    end

    test "detects 'when needed'" do
      assert Patterns.prn?("medication when needed")
    end

    test "returns false when no PRN indicator" do
      refute Patterns.prn?("metformin 500mg BID")
      refute Patterns.prn?("lisinopril 10mg daily")
    end
  end

  describe "Patterns.extract_duration/1" do
    test "extracts 'for X days'" do
      assert Patterns.extract_duration("for 7 days") == "7 days"
      assert Patterns.extract_duration("for 14 days") == "14 days"
    end

    test "extracts 'x X weeks'" do
      assert Patterns.extract_duration("x 2 weeks") == "2 weeks"
    end

    test "extracts months" do
      assert Patterns.extract_duration("for 3 months") == "3 months"
    end

    test "normalizes abbreviated units" do
      assert Patterns.extract_duration("for 7 d") == "7 days"
      assert Patterns.extract_duration("x 2 wk") == "2 weeks"
      assert Patterns.extract_duration("for 1 mo") == "1 months"
    end

    test "returns nil when no duration" do
      assert Patterns.extract_duration("no duration here") == nil
      assert Patterns.extract_duration("metformin 500mg BID") == nil
    end
  end

  describe "Patterns.extract_dose_range/1" do
    test "extracts dose range" do
      result = Patterns.extract_dose_range("50-100 mg")

      assert result.dose_low == 50.0
      assert result.dose_high == 100.0
      assert result.dose_unit == "mg"
    end

    test "handles decimal doses" do
      result = Patterns.extract_dose_range("0.5-1.0 mg")

      assert result.dose_low == 0.5
      assert result.dose_high == 1.0
    end

    test "returns nil for non-range" do
      assert Patterns.extract_dose_range("500 mg") == nil
    end
  end

  describe "Medication.extract/1 - rule_based" do
    test "extracts single medication entity" do
      context = %{text: "metformin 500mg PO BID", method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)

      assert length(entities) == 1
      entity = hd(entities)
      assert entity.type == :medication
      assert entity.text =~ ~r/metformin/i
      assert entity.attributes.drug_name == "metformin"
      assert entity.attributes.dose == 500.0
      assert entity.attributes.dose_unit == "mg"
      assert entity.attributes.route == "PO"
      assert entity.attributes.frequency == "BID"
      assert entity.extraction_method == :rule_based
    end

    test "extracts multiple medications" do
      context = %{
        text: "Patient on metformin 500mg BID and lisinopril 10mg daily",
        method: :rule_based,
        opts: []
      }

      {:ok, entities} = Medication.extract(context)

      assert length(entities) >= 2
      drug_names = Enum.map(entities, & &1.attributes.drug_name)
      assert "metformin" in drug_names
      assert "lisinopril" in drug_names
    end

    test "detects PRN from surrounding context" do
      context = %{text: "tylenol 500mg PRN for pain", method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)

      assert length(entities) == 1
      entity = hd(entities)
      assert entity.attributes.prn == true
    end

    test "extracts duration from surrounding context" do
      context = %{text: "amoxicillin 500mg TID for 7 days", method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)

      assert length(entities) == 1
      entity = hd(entities)
      assert entity.attributes.duration == "7 days"
    end

    test "calculates confidence based on completeness" do
      # Full specification should have higher confidence
      full_context = %{text: "metformin 500mg PO BID", method: :rule_based, opts: []}
      {:ok, [full_entity]} = Medication.extract(full_context)

      # Drug + dose only should have lower confidence
      partial_context = %{text: "metformin 500mg", method: :rule_based, opts: []}
      {:ok, [partial_entity]} = Medication.extract(partial_context)

      assert full_entity.confidence > partial_entity.confidence
    end

    test "filters by confidence threshold" do
      context = %{
        text: "metformin 500mg",
        method: :rule_based,
        opts: [confidence_threshold: 0.95]
      }

      {:ok, entities} = Medication.extract(context)

      # The simple extraction may not meet 0.95 threshold
      # All returned entities should be >= threshold
      Enum.each(entities, fn e ->
        assert e.confidence >= 0.95
      end)
    end

    test "returns empty list for no medications" do
      context = %{text: "Patient denies any medications", method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)
      assert entities == []
    end

    test "handles decimal doses" do
      context = %{text: "synthroid 0.05mg daily", method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)

      assert length(entities) >= 1
      entity = hd(entities)
      assert entity.attributes.dose == 0.05
    end

    test "includes correct text span" do
      text = "Take metformin 500mg daily"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)

      assert length(entities) == 1
      entity = hd(entities)
      # Verify the text matches the span in the original
      extracted = String.slice(text, entity.start_offset, entity.end_offset - entity.start_offset)
      assert extracted == entity.text
    end
  end

  describe "Medication.extract/1 - hybrid" do
    test "falls back to rule-based when transformer returns empty" do
      context = %{text: "metformin 500mg PO BID", method: :hybrid, opts: []}
      {:ok, entities} = Medication.extract(context)

      # Should still return results from rule-based
      assert length(entities) >= 1
      entity = hd(entities)
      assert entity.attributes.drug_name == "metformin"
    end
  end

  describe "Medication.extract/1 - transformer" do
    test "returns empty list (stub implementation)" do
      context = %{text: "metformin 500mg", method: :transformer, opts: []}
      {:ok, entities} = Medication.extract(context)

      # Transformer is currently a stub
      assert entities == []
    end
  end

  describe "Medication callbacks" do
    test "entity_type returns :medication" do
      assert Medication.entity_type() == :medication
    end

    test "supported_methods includes all methods" do
      methods = Medication.supported_methods()
      assert :rule_based in methods
      assert :transformer in methods
      assert :hybrid in methods
    end
  end

  describe "Entity struct fields" do
    test "entity has all required fields" do
      context = %{text: "metformin 500mg PO BID", method: :rule_based, opts: []}
      {:ok, [entity]} = Medication.extract(context)

      assert is_binary(entity.id)
      assert entity.type == :medication
      assert is_binary(entity.text)
      assert is_integer(entity.start_offset)
      assert is_integer(entity.end_offset)
      assert is_float(entity.confidence)
      assert is_map(entity.attributes)
      assert is_list(entity.warnings)
      assert is_map(entity.metadata)
    end
  end

  describe "edge cases" do
    test "handles empty string" do
      context = %{text: "", method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)
      assert entities == []
    end

    test "handles text with only whitespace" do
      context = %{text: "   \n\t  ", method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)
      assert entities == []
    end

    test "handles text with numbers but no drug" do
      context = %{text: "weight: 70kg, height: 180cm", method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)
      # May or may not extract - depends on pattern matching
      # Just verify no crash
      assert is_list(entities)
    end

    test "handles multiple occurrences of same medication" do
      context = %{
        text: "metformin 500mg in AM, metformin 500mg in PM",
        method: :rule_based,
        opts: []
      }

      {:ok, entities} = Medication.extract(context)

      # Should extract both occurrences
      assert length(entities) >= 2
    end
  end

  describe "clinical scenarios" do
    test "extracts from discharge summary style text" do
      text = """
      Medications at discharge:
      1. metformin 500mg PO BID
      2. lisinopril 10mg PO daily
      3. aspirin 81mg PO daily
      """

      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)

      assert length(entities) >= 3
      drug_names = Enum.map(entities, & &1.attributes.drug_name)
      assert "metformin" in drug_names
      assert "lisinopril" in drug_names
      assert "aspirin" in drug_names
    end

    test "extracts from inpatient medication list" do
      text = "Current meds: vancomycin 1g IV q12h, piperacillin-tazobactam 4.5g IV q8h"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)

      assert length(entities) >= 1
      # Vancomycin should definitely be extracted
      drug_names = Enum.map(entities, & &1.attributes.drug_name)
      assert "vancomycin" in drug_names
    end

    test "extracts PRN medications" do
      text = "Pain meds: morphine 2mg IV PRN q4h, acetaminophen 650mg PO PRN"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = Medication.extract(context)

      assert length(entities) >= 1
      # At least one should have PRN
      prn_entities = Enum.filter(entities, & &1.attributes.prn)
      assert length(prn_entities) >= 1
    end
  end
end
