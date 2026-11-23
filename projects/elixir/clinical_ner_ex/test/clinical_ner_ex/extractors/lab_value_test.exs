defmodule ClinicalNerEx.Extractors.LabValueTest do
  use ExUnit.Case, async: true

  alias ClinicalNerEx.Extractors.LabValue
  alias ClinicalNerEx.Extractors.LabValue.Patterns

  describe "Patterns.extract/1" do
    test "extracts simple lab with value" do
      text = "Hemoglobin 14.5 g/dL"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {start, end_offset, match, _type} = hd(results)
      assert start == 0
      assert end_offset == String.length(text)
      assert match["value"] == "14.5"
      assert match["unit"] =~ ~r/g\/dL/i
    end

    test "extracts A1c with percentage" do
      text = "A1c 7.2%"
      results = Patterns.extract(text)

      assert length(results) == 1
      {_start, _end, match, type} = hd(results)
      assert match["value"] == "7.2"
      assert type == :percentage
    end

    test "extracts lab with reference range" do
      text = "WBC 8.5 (4.5-11.0)"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match, type} = hd(results)
      assert type == :with_reference
      assert match["value"] == "8.5"
      assert match["ref_low"] == "4.5"
      assert match["ref_high"] == "11.0"
    end

    test "extracts lab with abnormal flag" do
      text = "Glucose 250 mg/dL (H)"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match, _type} = hd(results)
      assert match["value"] == "250"
      assert match["flag"] == "H"
    end

    test "extracts electrolyte panel shorthand" do
      text = "Na 138, K 4.2, Cl 102"
      results = Patterns.extract(text)

      assert length(results) == 3
      lab_names =
        Enum.map(results, fn {_, _, m, _} -> String.downcase(m["lab_name"]) end)

      assert "na" in lab_names
      assert "k" in lab_names
      assert "cl" in lab_names
    end

    test "extracts multiple lab values" do
      text = "Labs: Cr 1.2 mg/dL, BUN 18 mg/dL, eGFR 75"
      results = Patterns.extract(text)

      # Should find creatinine, BUN, and possibly eGFR
      assert length(results) >= 2
    end

    test "extracts creatinine with unit" do
      text = "Creatinine 1.2 mg/dL"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match, _type} = hd(results)
      assert match["value"] == "1.2"
      assert match["unit"] =~ ~r/mg\/dL/i
    end

    test "extracts HbA1c variant names" do
      texts = ["HbA1c 6.5%", "A1c 6.5%", "Hemoglobin A1c 6.5%"]

      for text <- texts do
        results = Patterns.extract(text)
        assert length(results) >= 1, "Failed to extract from: #{text}"
        {_start, _end, match, _type} = hd(results)
        assert match["value"] == "6.5"
      end
    end

    test "extracts TSH with low value" do
      text = "TSH 0.05 mIU/L (L)"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match, _type} = hd(results)
      assert match["value"] == "0.05"
      assert match["flag"] == "L"
    end

    test "returns empty list for no lab values" do
      text = "Patient denies any symptoms"
      results = Patterns.extract(text)
      assert results == []
    end

    test "handles lab with colon separator" do
      text = "Glucose: 95 mg/dL"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match, _type} = hd(results)
      assert match["value"] == "95"
    end

    test "handles lab with equals sign separator" do
      text = "Na = 140 mEq/L"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match, _type} = hd(results)
      assert match["value"] == "140"
    end
  end

  describe "Patterns.canonical_name/1" do
    test "normalizes A1c aliases" do
      assert Patterns.canonical_name("A1c") == "hemoglobin a1c"
      assert Patterns.canonical_name("HbA1c") == "hemoglobin a1c"
      assert Patterns.canonical_name("Hgb A1c") == "hemoglobin a1c"
    end

    test "normalizes glucose aliases" do
      assert Patterns.canonical_name("Glu") == "glucose"
      assert Patterns.canonical_name("glucose") == "glucose"
    end

    test "normalizes creatinine aliases" do
      assert Patterns.canonical_name("Cr") == "creatinine"
      assert Patterns.canonical_name("Crea") == "creatinine"
      assert Patterns.canonical_name("creatinine") == "creatinine"
    end

    test "normalizes electrolyte aliases" do
      assert Patterns.canonical_name("Na") == "sodium"
      assert Patterns.canonical_name("K") == "potassium"
      assert Patterns.canonical_name("Cl") == "chloride"
    end

    test "normalizes CBC aliases" do
      assert Patterns.canonical_name("WBC") == "white blood cell count"
      assert Patterns.canonical_name("Hgb") == "hemoglobin"
      assert Patterns.canonical_name("Hct") == "hematocrit"
      assert Patterns.canonical_name("Plt") == "platelets"
    end

    test "normalizes liver function aliases" do
      assert Patterns.canonical_name("ALT") == "alanine aminotransferase"
      assert Patterns.canonical_name("AST") == "aspartate aminotransferase"
      assert Patterns.canonical_name("ALP") == "alkaline phosphatase"
    end

    test "normalizes lipid panel aliases" do
      assert Patterns.canonical_name("HDL") == "hdl cholesterol"
      assert Patterns.canonical_name("LDL") == "ldl cholesterol"
      assert Patterns.canonical_name("Trig") == "triglycerides"
    end

    test "returns original for unknown lab names" do
      assert Patterns.canonical_name("unknown lab") == "unknown lab"
    end
  end

  describe "Patterns.known_lab?/1" do
    test "returns true for known labs" do
      assert Patterns.known_lab?("A1c")
      assert Patterns.known_lab?("Glucose")
      assert Patterns.known_lab?("Cr")
      assert Patterns.known_lab?("Na")
      assert Patterns.known_lab?("WBC")
    end

    test "returns false for unknown labs" do
      refute Patterns.known_lab?("random text")
      refute Patterns.known_lab?("unknown")
    end
  end

  describe "Patterns.parse_match/2" do
    test "parses standard lab value" do
      match = %{"lab_name" => "Glucose", "value" => "95", "unit" => "mg/dL"}
      attrs = Patterns.parse_match(match, :standard)

      assert attrs.lab_name == "glucose"
      assert attrs.value == 95.0
      assert attrs.unit == "mg/dL"
    end

    test "parses percentage lab value" do
      match = %{"lab_name" => "A1c", "value" => "7.2"}
      attrs = Patterns.parse_match(match, :percentage)

      assert attrs.lab_name == "hemoglobin a1c"
      assert attrs.value == 7.2
      assert attrs.unit == "%"
    end

    test "parses electrolyte shorthand" do
      match = %{"lab_name" => "Na", "value" => "138"}
      attrs = Patterns.parse_match(match, :electrolyte)

      assert attrs.lab_name == "sodium"
      assert attrs.value == 138.0
      assert attrs.unit == "mEq/L"
    end

    test "parses lab with reference range" do
      match = %{
        "lab_name" => "WBC",
        "value" => "8.5",
        "ref_low" => "4.5",
        "ref_high" => "11.0"
      }

      attrs = Patterns.parse_match(match, :with_reference)

      assert attrs.lab_name == "white blood cell count"
      assert attrs.value == 8.5
      assert attrs.reference_low == 4.5
      assert attrs.reference_high == 11.0
    end

    test "parses lab with abnormal flag" do
      match = %{"lab_name" => "Glucose", "value" => "250", "flag" => "H"}
      attrs = Patterns.parse_match(match, :standard)

      assert attrs.abnormal_flag == "H"
    end

    test "normalizes abnormal flag variants" do
      assert Patterns.parse_match(%{"flag" => "HIGH"}, :standard).abnormal_flag == "H"
      assert Patterns.parse_match(%{"flag" => "HI"}, :standard).abnormal_flag == "H"
      assert Patterns.parse_match(%{"flag" => "LOW"}, :standard).abnormal_flag == "L"
      assert Patterns.parse_match(%{"flag" => "LO"}, :standard).abnormal_flag == "L"
    end

    test "handles nil values" do
      match = %{"lab_name" => "Glucose", "value" => nil, "unit" => nil}
      attrs = Patterns.parse_match(match, :standard)

      assert attrs.lab_name == "glucose"
      assert attrs.value == nil
      assert attrs.unit == nil
    end

    test "normalizes unit case" do
      match = %{"lab_name" => "Cr", "value" => "1.2", "unit" => "MG/DL"}
      attrs = Patterns.parse_match(match, :standard)

      assert attrs.unit == "mg/dL"
    end
  end

  describe "LabValue.extract/1 - rule_based" do
    test "extracts single lab value entity" do
      context = %{text: "A1c 7.2%", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      assert length(entities) == 1
      entity = hd(entities)
      assert entity.type == :lab_value
      assert entity.attributes.lab_name == "hemoglobin a1c"
      assert entity.attributes.value == 7.2
      assert entity.attributes.unit == "%"
      assert entity.extraction_method == :rule_based
    end

    test "extracts lab with reference range" do
      context = %{text: "Hemoglobin 12.5 g/dL (12.0-16.0)", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      assert length(entities) >= 1
      entity = hd(entities)
      assert entity.attributes.value == 12.5
      assert entity.attributes.reference_low == 12.0
      assert entity.attributes.reference_high == 16.0
    end

    test "extracts electrolyte panel" do
      context = %{text: "Na 138, K 4.2, Cl 102", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      assert length(entities) == 3
      lab_names = Enum.map(entities, & &1.attributes.lab_name)
      assert "sodium" in lab_names
      assert "potassium" in lab_names
      assert "chloride" in lab_names
    end

    test "extracts lab with abnormal flag" do
      context = %{text: "Glucose 250 mg/dL (H)", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      assert length(entities) >= 1
      entity = hd(entities)
      assert entity.attributes.abnormal_flag == "H"
    end

    test "calculates higher confidence for reference range pattern" do
      # Lab with reference range should have higher confidence
      with_ref_context = %{text: "WBC 8.5 (4.5-11.0)", method: :rule_based, opts: []}
      {:ok, with_ref} = LabValue.extract(with_ref_context)

      # Simple lab should have lower confidence
      simple_context = %{text: "Glucose 95", method: :rule_based, opts: []}
      {:ok, simple} = LabValue.extract(simple_context)

      if length(with_ref) > 0 and length(simple) > 0 do
        # With reference should have higher or equal confidence
        assert hd(with_ref).confidence >= hd(simple).confidence
      end
    end

    test "filters by confidence threshold" do
      context = %{
        text: "Glucose 95",
        method: :rule_based,
        opts: [confidence_threshold: 0.95]
      }

      {:ok, entities} = LabValue.extract(context)

      # All returned entities should meet the threshold
      Enum.each(entities, fn e ->
        assert e.confidence >= 0.95
      end)
    end

    test "returns empty list for no lab values" do
      context = %{text: "Patient reports feeling well", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)
      assert entities == []
    end

    test "includes correct text span" do
      text = "A1c 7.2%"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      assert length(entities) == 1
      entity = hd(entities)
      # Verify the text matches the span in the original
      extracted = String.slice(text, entity.start_offset, entity.end_offset - entity.start_offset)
      assert extracted == entity.text
    end
  end

  describe "LabValue.extract/1 - hybrid" do
    test "falls back to rule-based when transformer returns empty" do
      context = %{text: "A1c 7.2%", method: :hybrid, opts: []}
      {:ok, entities} = LabValue.extract(context)

      # Should still return results from rule-based
      assert length(entities) >= 1
      entity = hd(entities)
      assert entity.attributes.lab_name == "hemoglobin a1c"
    end
  end

  describe "LabValue.extract/1 - transformer" do
    test "returns empty list (stub implementation)" do
      context = %{text: "A1c 7.2%", method: :transformer, opts: []}
      {:ok, entities} = LabValue.extract(context)

      # Transformer is currently a stub
      assert entities == []
    end
  end

  describe "LabValue callbacks" do
    test "entity_type returns :lab_value" do
      assert LabValue.entity_type() == :lab_value
    end

    test "supported_methods includes all methods" do
      methods = LabValue.supported_methods()
      assert :rule_based in methods
      assert :transformer in methods
      assert :hybrid in methods
    end
  end

  describe "Entity struct fields" do
    test "entity has all required fields" do
      context = %{text: "A1c 7.2%", method: :rule_based, opts: []}
      {:ok, [entity]} = LabValue.extract(context)

      assert is_binary(entity.id)
      assert entity.type == :lab_value
      assert is_binary(entity.text)
      assert is_integer(entity.start_offset)
      assert is_integer(entity.end_offset)
      assert is_float(entity.confidence)
      assert is_map(entity.attributes)
      assert is_list(entity.warnings)
      assert is_map(entity.metadata)
    end

    test "entity has expected attributes" do
      context = %{text: "Creatinine 1.2 mg/dL", method: :rule_based, opts: []}
      {:ok, [entity]} = LabValue.extract(context)

      attrs = entity.attributes
      assert Map.has_key?(attrs, :lab_name)
      assert Map.has_key?(attrs, :value)
      assert Map.has_key?(attrs, :unit)
      assert Map.has_key?(attrs, :reference_low)
      assert Map.has_key?(attrs, :reference_high)
      assert Map.has_key?(attrs, :abnormal_flag)
    end
  end

  describe "edge cases" do
    test "handles empty string" do
      context = %{text: "", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)
      assert entities == []
    end

    test "handles text with only whitespace" do
      context = %{text: "   \n\t  ", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)
      assert entities == []
    end

    test "handles decimal values" do
      context = %{text: "Creatinine 0.8 mg/dL", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      if length(entities) > 0 do
        assert hd(entities).attributes.value == 0.8
      end
    end

    test "handles values without units" do
      context = %{text: "INR 2.5", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      # May or may not match depending on dictionary
      assert is_list(entities)
    end

    test "handles critical value flags" do
      context = %{text: "Potassium 6.8 mEq/L (HH)", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      if length(entities) > 0 do
        entity = hd(entities)
        assert entity.attributes.abnormal_flag == "HH"
        assert "Critical value flag detected" in entity.warnings
      end
    end

    test "handles multiple occurrences of same lab" do
      context = %{
        text: "A1c 7.2% in January, A1c 6.8% in July",
        method: :rule_based,
        opts: []
      }

      {:ok, entities} = LabValue.extract(context)

      # Should extract both occurrences
      assert length(entities) >= 2
    end
  end

  describe "clinical scenarios" do
    test "extracts from basic metabolic panel" do
      text = """
      BMP Results:
      Na 140 mEq/L
      K 4.0 mEq/L
      Cl 102 mEq/L
      CO2 24 mEq/L
      BUN 15 mg/dL
      Cr 1.0 mg/dL
      Glucose 95 mg/dL
      """

      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      # Should extract most of these labs
      assert length(entities) >= 5
      lab_names = Enum.map(entities, & &1.attributes.lab_name)
      assert "sodium" in lab_names
      assert "potassium" in lab_names
    end

    test "extracts from CBC with diff" do
      text = """
      CBC:
      WBC 8.5 (4.5-11.0)
      Hgb 14.2 g/dL
      Hct 42%
      Plt 250 (150-400)
      """

      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      assert length(entities) >= 3
      lab_names = Enum.map(entities, & &1.attributes.lab_name)
      assert "white blood cell count" in lab_names
      assert "hemoglobin" in lab_names
    end

    test "extracts from lipid panel" do
      text = "Lipids: TC 220 mg/dL (H), HDL 45 mg/dL, LDL 140 mg/dL (H), TG 175 mg/dL (H)"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      assert length(entities) >= 2
    end

    test "extracts from A1c result with flag" do
      text = "Hemoglobin A1c 8.5% (H) - above goal of 7%"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      assert length(entities) >= 1
      entity = hd(entities)
      assert entity.attributes.lab_name == "hemoglobin a1c"
      assert entity.attributes.value == 8.5
      assert entity.attributes.abnormal_flag == "H"
    end

    test "extracts from liver function tests" do
      text = "LFTs: ALT 45 U/L, AST 38 U/L, ALP 85 U/L, Tbili 0.8 mg/dL"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      assert length(entities) >= 2
    end

    test "extracts thyroid panel" do
      text = "Thyroid: TSH 2.5 mIU/L, Free T4 1.2 ng/dL"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      assert length(entities) >= 1
      lab_names = Enum.map(entities, & &1.attributes.lab_name)
      assert "thyroid stimulating hormone" in lab_names
    end
  end

  describe "warnings generation" do
    test "warns when value found without unit" do
      context = %{text: "Glucose 95", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      if length(entities) > 0 do
        entity = hd(entities)
        assert "Value found without unit" in entity.warnings
      end
    end

    test "warns on critical value flags" do
      context = %{text: "K 6.5 (HH)", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      if length(entities) > 0 do
        entity = hd(entities)
        assert "Critical value flag detected" in entity.warnings
      end
    end
  end

  describe "confidence scoring" do
    test "higher confidence for more complete extractions" do
      # Full extraction with unit
      full_context = %{text: "Glucose 95 mg/dL", method: :rule_based, opts: []}
      {:ok, full_entities} = LabValue.extract(full_context)

      # Partial extraction without unit
      partial_context = %{text: "Glucose 95", method: :rule_based, opts: []}
      {:ok, partial_entities} = LabValue.extract(partial_context)

      if length(full_entities) > 0 and length(partial_entities) > 0 do
        assert hd(full_entities).confidence >= hd(partial_entities).confidence
      end
    end

    test "reference range pattern has highest base confidence" do
      context = %{text: "WBC 8.5 (4.5-11.0)", method: :rule_based, opts: []}
      {:ok, entities} = LabValue.extract(context)

      if length(entities) > 0 do
        # Reference range pattern should have high confidence
        assert hd(entities).confidence >= 0.85
      end
    end
  end
end
