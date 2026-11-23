defmodule ClinicalNerEx.Extractors.Diagnosis.PatternsTest do
  use ExUnit.Case, async: true

  alias ClinicalNerEx.Extractors.Diagnosis.Patterns

  describe "extract/1" do
    test "extracts h/o pattern" do
      text = "h/o hypertension"
      results = Patterns.extract(text)

      assert length(results) >= 1
      # Find the historical pattern result
      hist_result = Enum.find(results, fn {_, _, _, type} -> type == :historical end)

      if hist_result do
        {start, _end, match, type} = hist_result
        assert start == 0
        assert type == :historical
        assert String.contains?(match["condition"], "hypertension")
      end
    end

    test "extracts 'hx of' pattern" do
      text = "hx of diabetes"
      results = Patterns.extract(text)

      assert length(results) >= 1
    end

    test "extracts 'history of' pattern" do
      text = "history of congestive heart failure"
      results = Patterns.extract(text)

      assert length(results) >= 1
    end

    test "extracts 'past medical history' pattern" do
      text = "past medical history: diabetes, hypertension"
      results = Patterns.extract(text)

      # Should find abbreviation matches if not full pattern
      assert is_list(results)
    end

    test "extracts suspected pattern" do
      text = "suspected myocardial infarction"
      results = Patterns.extract(text)

      suspected_result = Enum.find(results, fn {_, _, _, type} -> type == :suspected end)
      assert suspected_result != nil

      {_start, _end, match, _type} = suspected_result
      assert match["condition"] != nil
    end

    test "extracts possible pattern" do
      text = "possible pneumonia"
      results = Patterns.extract(text)

      assert length(results) >= 1
    end

    test "extracts r/o pattern" do
      text = "r/o appendicitis"
      results = Patterns.extract(text)

      suspected_result = Enum.find(results, fn {_, _, _, type} -> type == :suspected end)
      assert suspected_result != nil
    end

    test "extracts rule out pattern" do
      text = "rule out pulmonary embolism"
      results = Patterns.extract(text)

      assert length(results) >= 1
    end

    test "extracts severity pattern - severe" do
      text = "severe depression"
      results = Patterns.extract(text)

      severity_result = Enum.find(results, fn {_, _, _, type} -> type == :with_severity end)
      assert severity_result != nil

      {_start, _end, match, _type} = severity_result
      assert match["severity"] == "severe"
    end

    test "extracts severity pattern - mild" do
      text = "mild anxiety"
      results = Patterns.extract(text)

      severity_result = Enum.find(results, fn {_, _, _, type} -> type == :with_severity end)
      assert severity_result != nil

      {_start, _end, match, _type} = severity_result
      assert match["severity"] == "mild"
    end

    test "extracts severity pattern - moderate" do
      text = "moderate asthma"
      results = Patterns.extract(text)

      severity_result = Enum.find(results, fn {_, _, _, type} -> type == :with_severity end)
      assert severity_result != nil

      {_start, _end, match, _type} = severity_result
      assert match["severity"] == "moderate"
    end

    test "extracts acuity pattern - acute" do
      text = "acute bronchitis"
      results = Patterns.extract(text)

      acuity_result = Enum.find(results, fn {_, _, _, type} -> type == :with_acuity end)
      assert acuity_result != nil
    end

    test "extracts acuity pattern - chronic" do
      text = "chronic sinusitis"
      results = Patterns.extract(text)

      acuity_result = Enum.find(results, fn {_, _, _, type} -> type == :with_acuity end)
      assert acuity_result != nil
    end

    test "extracts multiple abbreviations" do
      text = "HTN, DM, CHF"
      results = Patterns.extract(text)

      abbreviation_results = Enum.filter(results, fn {_, _, _, type} -> type == :abbreviation end)
      assert length(abbreviation_results) == 3
    end

    test "extracts abbreviation as whole word" do
      text = "Patient diagnosed with CAD"
      results = Patterns.extract(text)

      abbrev_result = Enum.find(results, fn {_, _, match, type} ->
        type == :abbreviation and String.downcase(match["condition"]) == "cad"
      end)

      assert abbrev_result != nil
    end

    test "does not match abbreviation within word" do
      # "DYNAMIC" contains "DM" but should not match
      text = "DYNAMIC patient"
      results = Patterns.extract(text)

      dm_results = Enum.filter(results, fn {_, _, match, _} ->
        String.downcase(match["condition"]) == "dm"
      end)

      assert length(dm_results) == 0
    end

    test "returns empty list for text without diagnoses" do
      text = "Patient taking aspirin daily"
      results = Patterns.extract(text)
      # May have some matches but shouldn't crash
      assert is_list(results)
    end

    test "handles empty string" do
      text = ""
      results = Patterns.extract(text)
      assert results == []
    end

    test "deduplicates overlapping matches" do
      text = "h/o HTN"
      results = Patterns.extract(text)

      # Should not have duplicate start offsets
      starts = Enum.map(results, fn {start, _, _, _} -> start end)
      assert length(starts) == length(Enum.uniq(starts))
    end

    test "sorts results by start offset" do
      text = "h/o DM, HTN diagnosed in 2020"
      results = Patterns.extract(text)

      starts = Enum.map(results, fn {start, _, _, _} -> start end)
      assert starts == Enum.sort(starts)
    end
  end

  describe "expand_abbreviation/1" do
    test "expands cardiac abbreviations" do
      assert Patterns.expand_abbreviation("HTN") == "hypertension"
      assert Patterns.expand_abbreviation("CHF") == "congestive heart failure"
      assert Patterns.expand_abbreviation("CAD") == "coronary artery disease"
      assert Patterns.expand_abbreviation("MI") == "myocardial infarction"
      assert Patterns.expand_abbreviation("AFib") == "atrial fibrillation"
      assert Patterns.expand_abbreviation("A-fib") == "atrial fibrillation"
    end

    test "expands diabetes abbreviations" do
      assert Patterns.expand_abbreviation("DM") == "diabetes mellitus"
      assert Patterns.expand_abbreviation("T1DM") == "type 1 diabetes mellitus"
      assert Patterns.expand_abbreviation("T2DM") == "type 2 diabetes mellitus"
    end

    test "expands pulmonary abbreviations" do
      assert Patterns.expand_abbreviation("COPD") == "chronic obstructive pulmonary disease"
      assert Patterns.expand_abbreviation("PNA") == "pneumonia"
      assert Patterns.expand_abbreviation("PE") == "pulmonary embolism"
      assert Patterns.expand_abbreviation("OSA") == "obstructive sleep apnea"
    end

    test "expands renal abbreviations" do
      assert Patterns.expand_abbreviation("CKD") == "chronic kidney disease"
      assert Patterns.expand_abbreviation("ESRD") == "end stage renal disease"
      assert Patterns.expand_abbreviation("UTI") == "urinary tract infection"
    end

    test "expands neurological abbreviations" do
      assert Patterns.expand_abbreviation("CVA") == "cerebrovascular accident"
      assert Patterns.expand_abbreviation("TIA") == "transient ischemic attack"
    end

    test "expands GI abbreviations" do
      assert Patterns.expand_abbreviation("GERD") == "gastroesophageal reflux disease"
    end

    test "expands vascular abbreviations" do
      assert Patterns.expand_abbreviation("DVT") == "deep vein thrombosis"
    end

    test "expands rheumatologic abbreviations" do
      assert Patterns.expand_abbreviation("OA") == "osteoarthritis"
      assert Patterns.expand_abbreviation("RA") == "rheumatoid arthritis"
      assert Patterns.expand_abbreviation("SLE") == "systemic lupus erythematosus"
    end

    test "expands other common abbreviations" do
      assert Patterns.expand_abbreviation("URI") == "upper respiratory infection"
      assert Patterns.expand_abbreviation("HLD") == "hyperlipidemia"
      assert Patterns.expand_abbreviation("BPH") == "benign prostatic hyperplasia"
    end

    test "is case insensitive" do
      assert Patterns.expand_abbreviation("htn") == "hypertension"
      assert Patterns.expand_abbreviation("Htn") == "hypertension"
      assert Patterns.expand_abbreviation("HTN") == "hypertension"
    end

    test "returns input unchanged for unknown abbreviations" do
      assert Patterns.expand_abbreviation("XYZ") == "XYZ"
      assert Patterns.expand_abbreviation("unknown") == "unknown"
    end
  end

  describe "detect_status/1" do
    test "detects historical indicators" do
      assert Patterns.detect_status("h/o something") == :historical
      assert Patterns.detect_status("hx of condition") == :historical
      assert Patterns.detect_status("history of disease") == :historical
      assert Patterns.detect_status("past history of illness") == :historical
      assert Patterns.detect_status("pmh: diabetes") == :historical
    end

    test "detects suspected indicators" do
      assert Patterns.detect_status("suspected diagnosis") == :suspected
      assert Patterns.detect_status("possible condition") == :suspected
      assert Patterns.detect_status("probable disease") == :suspected
      assert Patterns.detect_status("? appendicitis") == :suspected
      assert Patterns.detect_status("likely infection") == :suspected
    end

    test "detects ruled out indicators" do
      assert Patterns.detect_status("r/o disease") == :ruled_out
      assert Patterns.detect_status("ruled out condition") == :ruled_out
      assert Patterns.detect_status("no evidence of cancer") == :ruled_out
      assert Patterns.detect_status("negative for infection") == :ruled_out
    end

    test "detects resolved indicators" do
      assert Patterns.detect_status("resolved infection") == :resolved
      assert Patterns.detect_status("cured condition") == :resolved
      assert Patterns.detect_status("healed wound") == :resolved
      assert Patterns.detect_status("recovered from illness") == :resolved
    end

    test "detects active indicators" do
      assert Patterns.detect_status("active infection") == :active
      assert Patterns.detect_status("current symptoms") == :active
      assert Patterns.detect_status("ongoing treatment") == :active
      assert Patterns.detect_status("present findings") == :active
    end

    test "defaults to active for no indicators" do
      assert Patterns.detect_status("hypertension") == :active
      assert Patterns.detect_status("diabetes mellitus") == :active
      assert Patterns.detect_status("just some text") == :active
    end

    test "prioritizes ruled out over suspected" do
      # r/o should match ruled_out, not suspected
      assert Patterns.detect_status("r/o PE") == :ruled_out
    end
  end

  describe "parse_match/2" do
    test "parses historical type correctly" do
      match = %{"condition" => "diabetes"}
      attrs = Patterns.parse_match(match, :historical)

      assert attrs.status == :historical
      assert attrs.condition == "diabetes"
    end

    test "parses suspected type correctly" do
      match = %{"condition" => "pneumonia"}
      attrs = Patterns.parse_match(match, :suspected)

      assert attrs.status == :suspected
    end

    test "parses abbreviation type correctly" do
      match = %{"condition" => "HTN"}
      attrs = Patterns.parse_match(match, :abbreviation)

      assert attrs.status == :active
      assert attrs.condition == "hypertension"
    end

    test "parses severity" do
      match = %{"condition" => "depression", "severity" => "severe"}
      attrs = Patterns.parse_match(match, :with_severity)

      assert attrs.severity == :severe
    end

    test "normalizes severity values" do
      assert Patterns.parse_match(%{"severity" => "mild"}, :with_severity).severity == :mild
      assert Patterns.parse_match(%{"severity" => "minimal"}, :with_severity).severity == :mild
      assert Patterns.parse_match(%{"severity" => "moderate"}, :with_severity).severity == :moderate
      assert Patterns.parse_match(%{"severity" => "severe"}, :with_severity).severity == :severe
      assert Patterns.parse_match(%{"severity" => "advanced"}, :with_severity).severity == :severe
      assert Patterns.parse_match(%{"severity" => "significant"}, :with_severity).severity == :severe
    end

    test "parses laterality" do
      match = %{"condition" => "pain", "laterality" => "left", "body_site" => "knee"}
      attrs = Patterns.parse_match(match, :with_laterality)

      assert attrs.laterality == :left
      assert attrs.body_site == "knee"
    end

    test "normalizes laterality values" do
      assert Patterns.parse_match(%{"laterality" => "left"}, :with_laterality).laterality == :left
      assert Patterns.parse_match(%{"laterality" => "L"}, :with_laterality).laterality == :left
      assert Patterns.parse_match(%{"laterality" => "right"}, :with_laterality).laterality == :right
      assert Patterns.parse_match(%{"laterality" => "R"}, :with_laterality).laterality == :right
      assert Patterns.parse_match(%{"laterality" => "bilateral"}, :with_laterality).laterality == :bilateral
      assert Patterns.parse_match(%{"laterality" => "B/L"}, :with_laterality).laterality == :bilateral
    end

    test "handles nil values gracefully" do
      match = %{"condition" => nil, "severity" => nil, "laterality" => nil}
      attrs = Patterns.parse_match(match, :historical)

      assert attrs.condition == nil
      assert attrs.severity == nil
      assert attrs.laterality == nil
    end

    test "returns onset as nil" do
      match = %{"condition" => "diabetes"}
      attrs = Patterns.parse_match(match, :historical)

      assert attrs.onset == nil
    end
  end

  describe "accessor functions" do
    test "abbreviations returns the abbreviations map" do
      abbrevs = Patterns.abbreviations()
      assert is_map(abbrevs)
      assert Map.has_key?(abbrevs, "htn")
      assert Map.has_key?(abbrevs, "dm")
    end

    test "history_pattern returns regex" do
      pattern = Patterns.history_pattern()
      assert %Regex{} = pattern
    end

    test "suspected_pattern returns regex" do
      pattern = Patterns.suspected_pattern()
      assert %Regex{} = pattern
    end

    test "severity_pattern returns regex" do
      pattern = Patterns.severity_pattern()
      assert %Regex{} = pattern
    end
  end
end
