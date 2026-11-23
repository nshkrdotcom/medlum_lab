defmodule ClinicalNerEx.Extractors.LabValue.PatternsTest do
  use ExUnit.Case, async: true

  alias ClinicalNerEx.Extractors.LabValue.Patterns

  describe "extract/1 - basic patterns" do
    test "extracts lab with standard format" do
      results = Patterns.extract("Creatinine 1.2 mg/dL")

      assert length(results) == 1
      {start, end_offset, match, _type} = hd(results)
      assert start == 0
      assert end_offset == 20
      assert match["lab_name"] =~ ~r/creatinine/i
      assert match["value"] == "1.2"
      assert match["unit"] =~ ~r/mg\/dL/i
    end

    test "extracts lab with percentage" do
      results = Patterns.extract("Hematocrit 42%")

      assert length(results) == 1
      {_start, _end, match, type} = hd(results)
      assert type == :percentage
      assert match["value"] == "42"
    end

    test "extracts lab with reference range" do
      results = Patterns.extract("Hemoglobin 14.5 g/dL (12.0-17.0)")

      assert length(results) >= 1
      {_start, _end, match, type} = hd(results)
      assert type == :with_reference
      assert match["value"] == "14.5"
      assert match["ref_low"] == "12.0"
      assert match["ref_high"] == "17.0"
    end

    test "extracts lab with abnormal flag" do
      results = Patterns.extract("Glucose 250 mg/dL (H)")

      assert length(results) >= 1
      {_start, _end, match, _type} = hd(results)
      assert match["value"] == "250"
      assert match["flag"] == "H"
    end

    test "extracts electrolyte shorthand" do
      results = Patterns.extract("Na 140")

      assert length(results) == 1
      {_start, _end, match, type} = hd(results)
      assert type == :electrolyte
      assert match["lab_name"] =~ ~r/na/i
      assert match["value"] == "140"
    end
  end

  describe "extract/1 - multiple labs" do
    test "extracts multiple labs in sequence" do
      results = Patterns.extract("Na 140, K 4.0, Cl 102")

      assert length(results) == 3
    end

    test "extracts labs with different patterns" do
      text = "A1c 7.2%, Creatinine 1.2 mg/dL, WBC 8.5 (4.5-11.0)"
      results = Patterns.extract(text)

      assert length(results) >= 3
      types = Enum.map(results, fn {_, _, _, t} -> t end)
      assert :percentage in types or :standard in types
    end

    test "handles labs on separate lines" do
      text = """
      Glucose 95 mg/dL
      BUN 18 mg/dL
      Creatinine 1.0 mg/dL
      """

      results = Patterns.extract(text)
      assert length(results) >= 2
    end
  end

  describe "extract/1 - edge cases" do
    test "handles decimal values" do
      results = Patterns.extract("Creatinine 0.8 mg/dL")

      assert length(results) >= 1
      {_start, _end, match, _type} = hd(results)
      assert match["value"] == "0.8"
    end

    test "handles very small decimal values" do
      results = Patterns.extract("TSH 0.05 mIU/L")

      assert length(results) >= 1
      {_start, _end, match, _type} = hd(results)
      assert match["value"] == "0.05"
    end

    test "handles large values" do
      results = Patterns.extract("Triglycerides 500 mg/dL")

      assert length(results) >= 1
      {_start, _end, match, _type} = hd(results)
      assert match["value"] == "500"
    end

    test "handles colon separator" do
      results = Patterns.extract("Glucose: 95 mg/dL")

      assert length(results) >= 1
    end

    test "handles equals sign separator" do
      results = Patterns.extract("Na = 140")

      assert length(results) >= 1
    end

    test "returns empty for text without labs" do
      results = Patterns.extract("Patient feels well today")
      assert results == []
    end

    test "returns empty for empty string" do
      results = Patterns.extract("")
      assert results == []
    end
  end

  describe "canonical_name/1" do
    test "normalizes common A1c variations" do
      assert Patterns.canonical_name("a1c") == "hemoglobin a1c"
      assert Patterns.canonical_name("A1c") == "hemoglobin a1c"
      assert Patterns.canonical_name("HbA1c") == "hemoglobin a1c"
      assert Patterns.canonical_name("hba1c") == "hemoglobin a1c"
      assert Patterns.canonical_name("Hemoglobin A1c") == "hemoglobin a1c"
    end

    test "normalizes electrolyte names" do
      assert Patterns.canonical_name("Na") == "sodium"
      assert Patterns.canonical_name("na") == "sodium"
      assert Patterns.canonical_name("Na+") == "sodium"
      assert Patterns.canonical_name("K") == "potassium"
      assert Patterns.canonical_name("k+") == "potassium"
      assert Patterns.canonical_name("Cl") == "chloride"
      assert Patterns.canonical_name("cl-") == "chloride"
    end

    test "normalizes renal function labs" do
      assert Patterns.canonical_name("Cr") == "creatinine"
      assert Patterns.canonical_name("cr") == "creatinine"
      assert Patterns.canonical_name("Crea") == "creatinine"
      assert Patterns.canonical_name("BUN") == "blood urea nitrogen"
      assert Patterns.canonical_name("eGFR") == "estimated glomerular filtration rate"
    end

    test "normalizes CBC components" do
      assert Patterns.canonical_name("WBC") == "white blood cell count"
      assert Patterns.canonical_name("wbc") == "white blood cell count"
      assert Patterns.canonical_name("Hgb") == "hemoglobin"
      assert Patterns.canonical_name("Hb") == "hemoglobin"
      assert Patterns.canonical_name("Hct") == "hematocrit"
      assert Patterns.canonical_name("Plt") == "platelets"
    end

    test "normalizes liver function labs" do
      assert Patterns.canonical_name("ALT") == "alanine aminotransferase"
      assert Patterns.canonical_name("SGPT") == "alanine aminotransferase"
      assert Patterns.canonical_name("AST") == "aspartate aminotransferase"
      assert Patterns.canonical_name("SGOT") == "aspartate aminotransferase"
      assert Patterns.canonical_name("ALP") == "alkaline phosphatase"
      assert Patterns.canonical_name("Tbili") == "total bilirubin"
    end

    test "normalizes lipid panel labs" do
      assert Patterns.canonical_name("Cholesterol") == "total cholesterol"
      assert Patterns.canonical_name("TC") == "total cholesterol"
      assert Patterns.canonical_name("HDL") == "hdl cholesterol"
      assert Patterns.canonical_name("LDL") == "ldl cholesterol"
      assert Patterns.canonical_name("Trig") == "triglycerides"
      assert Patterns.canonical_name("TG") == "triglycerides"
    end

    test "normalizes thyroid labs" do
      assert Patterns.canonical_name("TSH") == "thyroid stimulating hormone"
      assert Patterns.canonical_name("FT4") == "free t4"
    end

    test "normalizes coagulation labs" do
      assert Patterns.canonical_name("INR") == "international normalized ratio"
      assert Patterns.canonical_name("PT") == "prothrombin time"
      assert Patterns.canonical_name("PTT") == "partial thromboplastin time"
    end

    test "returns original for unknown labs" do
      assert Patterns.canonical_name("RandomLab") == "randomlab"
      assert Patterns.canonical_name("Unknown Test") == "unknown test"
    end
  end

  describe "known_lab?/1" do
    test "returns true for all common labs" do
      common_labs = [
        "A1c",
        "Glucose",
        "Cr",
        "BUN",
        "Na",
        "K",
        "Cl",
        "WBC",
        "Hgb",
        "Hct",
        "Plt",
        "TSH",
        "ALT",
        "AST",
        "Cholesterol",
        "HDL",
        "LDL"
      ]

      for lab <- common_labs do
        assert Patterns.known_lab?(lab), "Expected #{lab} to be a known lab"
      end
    end

    test "returns false for unknown strings" do
      refute Patterns.known_lab?("randomtext")
      refute Patterns.known_lab?("patient")
      refute Patterns.known_lab?("temperature")
    end

    test "is case insensitive" do
      assert Patterns.known_lab?("glucose")
      assert Patterns.known_lab?("GLUCOSE")
      assert Patterns.known_lab?("Glucose")
    end
  end

  describe "parse_match/2 - value parsing" do
    test "parses integer values" do
      match = %{"value" => "140"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.value == 140.0
    end

    test "parses decimal values" do
      match = %{"value" => "7.2"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.value == 7.2
    end

    test "parses small decimal values" do
      match = %{"value" => "0.05"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.value == 0.05
    end

    test "handles nil value" do
      match = %{"value" => nil}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.value == nil
    end

    test "handles empty value" do
      match = %{"value" => ""}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.value == nil
    end
  end

  describe "parse_match/2 - unit normalization" do
    test "normalizes mg/dL case" do
      match = %{"unit" => "mg/dl"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.unit == "mg/dL"
    end

    test "normalizes g/dL case" do
      match = %{"unit" => "G/DL"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.unit == "g/dL"
    end

    test "normalizes mEq/L case" do
      match = %{"unit" => "meq/l"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.unit == "mEq/L"
    end

    test "normalizes U/L case" do
      match = %{"unit" => "u/l"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.unit == "U/L"
    end

    test "provides default unit for percentage pattern" do
      match = %{"lab_name" => "A1c", "value" => "7.2"}
      attrs = Patterns.parse_match(match, :percentage)
      assert attrs.unit == "%"
    end

    test "provides default unit for electrolyte pattern" do
      match = %{"lab_name" => "Na", "value" => "140"}
      attrs = Patterns.parse_match(match, :electrolyte)
      assert attrs.unit == "mEq/L"
    end
  end

  describe "parse_match/2 - flag normalization" do
    test "normalizes H flag" do
      match = %{"flag" => "H"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.abnormal_flag == "H"
    end

    test "normalizes HIGH to H" do
      match = %{"flag" => "HIGH"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.abnormal_flag == "H"
    end

    test "normalizes HI to H" do
      match = %{"flag" => "HI"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.abnormal_flag == "H"
    end

    test "normalizes L flag" do
      match = %{"flag" => "L"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.abnormal_flag == "L"
    end

    test "normalizes LOW to L" do
      match = %{"flag" => "LOW"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.abnormal_flag == "L"
    end

    test "normalizes LO to L" do
      match = %{"flag" => "LO"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.abnormal_flag == "L"
    end

    test "preserves HH flag" do
      match = %{"flag" => "HH"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.abnormal_flag == "HH"
    end

    test "preserves LL flag" do
      match = %{"flag" => "LL"}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.abnormal_flag == "LL"
    end

    test "handles nil flag" do
      match = %{"flag" => nil}
      attrs = Patterns.parse_match(match, :standard)
      assert attrs.abnormal_flag == nil
    end
  end

  describe "parse_match/2 - reference range" do
    test "parses reference range values" do
      match = %{"ref_low" => "4.5", "ref_high" => "11.0"}
      attrs = Patterns.parse_match(match, :with_reference)

      assert attrs.reference_low == 4.5
      assert attrs.reference_high == 11.0
    end

    test "handles nil reference range" do
      match = %{"ref_low" => nil, "ref_high" => nil}
      attrs = Patterns.parse_match(match, :standard)

      assert attrs.reference_low == nil
      assert attrs.reference_high == nil
    end
  end

  describe "lab_aliases/0" do
    test "returns a map" do
      aliases = Patterns.lab_aliases()
      assert is_map(aliases)
    end

    test "contains common lab aliases" do
      aliases = Patterns.lab_aliases()
      assert Map.has_key?(aliases, "a1c")
      assert Map.has_key?(aliases, "glucose")
      assert Map.has_key?(aliases, "cr")
      assert Map.has_key?(aliases, "na")
    end
  end

  describe "flag_normalization/0" do
    test "returns a map" do
      flags = Patterns.flag_normalization()
      assert is_map(flags)
    end

    test "contains common flag mappings" do
      flags = Patterns.flag_normalization()
      assert Map.has_key?(flags, "high")
      assert Map.has_key?(flags, "low")
      assert Map.has_key?(flags, "h")
      assert Map.has_key?(flags, "l")
    end
  end
end
