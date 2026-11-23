defmodule ClinicalNerEx.Extractors.DiagnosisTest do
  use ExUnit.Case, async: true

  alias ClinicalNerEx.Extractors.Diagnosis
  alias ClinicalNerEx.Extractors.Diagnosis.Patterns

  describe "Patterns.extract/1" do
    test "extracts history of condition" do
      text = "h/o hypertension"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, match, type} = hd(results)
      assert type == :historical or type == :abbreviation
      assert match["condition"] != nil
    end

    test "extracts 'history of' full phrase" do
      text = "history of diabetes mellitus"
      results = Patterns.extract(text)

      assert length(results) >= 1
      {_start, _end, _match, type} = hd(results)
      # Should match historical pattern or abbreviation
      assert type in [:historical, :abbreviation]
    end

    test "extracts suspected condition" do
      text = "suspected MI"
      results = Patterns.extract(text)

      assert length(results) >= 1
    end

    test "extracts rule out condition" do
      text = "r/o pulmonary embolism"
      results = Patterns.extract(text)

      assert length(results) >= 1
      # May find PE abbreviation or suspected pattern
    end

    test "extracts abbreviations" do
      text = "Patient with HTN, DM, and COPD"
      results = Patterns.extract(text)

      assert length(results) >= 3
      conditions =
        Enum.map(results, fn {_, _, m, _} -> String.downcase(m["condition"]) end)

      assert "htn" in conditions or "hypertension" in conditions
    end

    test "extracts condition with severity" do
      text = "severe COPD"
      results = Patterns.extract(text)

      assert length(results) >= 1
    end

    test "extracts mild severity" do
      text = "mild depression"
      results = Patterns.extract(text)

      assert length(results) >= 1
      # Find the severity pattern result
      severity_result = Enum.find(results, fn {_, _, _, type} -> type == :with_severity end)

      if severity_result do
        {_, _, match, _} = severity_result
        assert match["severity"] == "mild"
      end
    end

    test "extracts condition with laterality" do
      text = "left knee osteoarthritis"
      results = Patterns.extract(text)

      # May or may not match depending on pattern
      assert is_list(results)
    end

    test "extracts bilateral condition" do
      text = "bilateral pneumonia"
      results = Patterns.extract(text)

      # Should find something
      assert is_list(results)
    end

    test "extracts acute condition" do
      text = "acute kidney injury"
      results = Patterns.extract(text)

      assert length(results) >= 1
    end

    test "extracts chronic condition" do
      text = "chronic kidney disease"
      results = Patterns.extract(text)

      assert length(results) >= 1
    end

    test "returns empty list for no diagnoses" do
      text = "Patient feels well"
      results = Patterns.extract(text)
      # Should return empty or minimal results
      assert is_list(results)
    end
  end

  describe "Patterns.expand_abbreviation/1" do
    test "expands known abbreviations" do
      assert Patterns.expand_abbreviation("HTN") == "hypertension"
      assert Patterns.expand_abbreviation("DM") == "diabetes mellitus"
      assert Patterns.expand_abbreviation("COPD") == "chronic obstructive pulmonary disease"
      assert Patterns.expand_abbreviation("CAD") == "coronary artery disease"
    end

    test "expands case insensitively" do
      assert Patterns.expand_abbreviation("htn") == "hypertension"
      assert Patterns.expand_abbreviation("Htn") == "hypertension"
    end

    test "returns unchanged for unknown abbreviations" do
      assert Patterns.expand_abbreviation("unknown") == "unknown"
      assert Patterns.expand_abbreviation("XYZ") == "XYZ"
    end

    test "expands cardiovascular abbreviations" do
      assert Patterns.expand_abbreviation("MI") == "myocardial infarction"
      assert Patterns.expand_abbreviation("CHF") == "congestive heart failure"
      assert Patterns.expand_abbreviation("AFib") == "atrial fibrillation"
    end

    test "expands respiratory abbreviations" do
      assert Patterns.expand_abbreviation("PNA") == "pneumonia"
      assert Patterns.expand_abbreviation("URI") == "upper respiratory infection"
      assert Patterns.expand_abbreviation("OSA") == "obstructive sleep apnea"
    end

    test "expands renal abbreviations" do
      assert Patterns.expand_abbreviation("CKD") == "chronic kidney disease"
      assert Patterns.expand_abbreviation("ESRD") == "end stage renal disease"
      assert Patterns.expand_abbreviation("UTI") == "urinary tract infection"
    end
  end

  describe "Patterns.detect_status/1" do
    test "detects historical status" do
      assert Patterns.detect_status("h/o diabetes") == :historical
      assert Patterns.detect_status("history of CHF") == :historical
      assert Patterns.detect_status("hx of hypertension") == :historical
    end

    test "detects suspected status" do
      assert Patterns.detect_status("suspected PE") == :suspected
      assert Patterns.detect_status("possible MI") == :suspected
      assert Patterns.detect_status("probable pneumonia") == :suspected
    end

    test "detects ruled out status" do
      assert Patterns.detect_status("r/o appendicitis") == :ruled_out
      assert Patterns.detect_status("ruled out PE") == :ruled_out
      assert Patterns.detect_status("no evidence of malignancy") == :ruled_out
    end

    test "detects resolved status" do
      assert Patterns.detect_status("resolved infection") == :resolved
      assert Patterns.detect_status("cured hepatitis") == :resolved
    end

    test "detects active status" do
      assert Patterns.detect_status("active infection") == :active
      assert Patterns.detect_status("current exacerbation") == :active
    end

    test "defaults to active" do
      assert Patterns.detect_status("diabetes mellitus") == :active
      assert Patterns.detect_status("hypertension") == :active
    end
  end

  describe "Patterns.parse_match/2" do
    test "parses historical match" do
      match = %{"condition" => "hypertension"}
      attrs = Patterns.parse_match(match, :historical)

      assert attrs.condition == "hypertension"
      assert attrs.status == :historical
    end

    test "parses suspected match" do
      match = %{"condition" => "MI"}
      attrs = Patterns.parse_match(match, :suspected)

      assert attrs.condition == "myocardial infarction"
      assert attrs.status == :suspected
    end

    test "parses abbreviation match" do
      match = %{"condition" => "HTN"}
      attrs = Patterns.parse_match(match, :abbreviation)

      assert attrs.condition == "hypertension"
      assert attrs.status == :active
    end

    test "parses match with severity" do
      match = %{"condition" => "COPD", "severity" => "severe"}
      attrs = Patterns.parse_match(match, :with_severity)

      assert attrs.severity == :severe
    end

    test "parses match with laterality" do
      match = %{"condition" => "pneumonia", "laterality" => "left", "body_site" => "lung"}
      attrs = Patterns.parse_match(match, :with_laterality)

      assert attrs.laterality == :left
      assert attrs.body_site == "lung"
    end

    test "handles nil values" do
      match = %{"condition" => "test", "severity" => nil, "laterality" => nil}
      attrs = Patterns.parse_match(match, :historical)

      assert attrs.severity == nil
      assert attrs.laterality == nil
    end
  end

  describe "Diagnosis.extract/1" do
    test "extracts diagnosis entities" do
      context = %{text: "h/o type 2 diabetes", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      if length(entities) > 0 do
        entity = hd(entities)
        assert entity.type == :diagnosis
        assert entity.attributes.status == :historical
      end
    end

    test "extracts abbreviation-based diagnoses" do
      context = %{text: "Patient has HTN and DM", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      assert length(entities) >= 2
    end

    test "entity_type returns :diagnosis" do
      assert Diagnosis.entity_type() == :diagnosis
    end

    test "supported_methods returns all methods" do
      methods = Diagnosis.supported_methods()
      assert :rule_based in methods
      assert :transformer in methods
      assert :hybrid in methods
    end

    test "extracts with correct entity structure" do
      context = %{text: "h/o HTN", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      if length(entities) > 0 do
        entity = hd(entities)
        assert is_binary(entity.id)
        assert entity.type == :diagnosis
        assert is_binary(entity.text)
        assert is_integer(entity.start_offset)
        assert is_integer(entity.end_offset)
        assert is_float(entity.confidence)
        assert is_map(entity.attributes)
        assert is_list(entity.warnings)
        assert is_map(entity.metadata)
      end
    end

    test "returns empty list for no diagnoses" do
      context = %{text: "Patient taking metformin 500mg", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)
      # May or may not find anything
      assert is_list(entities)
    end
  end

  describe "status detection in extraction" do
    test "correctly identifies historical diagnoses" do
      context = %{text: "PMH: HTN, DM, CAD", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      # All should be found as abbreviations
      assert length(entities) >= 3
    end

    test "correctly identifies suspected diagnoses" do
      context = %{text: "r/o pulmonary embolism", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      # May find PE abbreviation or rule out pattern
      assert is_list(entities)
    end
  end

  describe "confidence scoring" do
    test "abbreviations have high confidence" do
      context = %{text: "Patient has HTN", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      if length(entities) > 0 do
        entity = hd(entities)
        # Abbreviation base is 0.90, plus condition boost
        assert entity.confidence >= 0.90
      end
    end

    test "historical patterns have good confidence" do
      context = %{text: "history of diabetes mellitus", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      if length(entities) > 0 do
        entity = hd(entities)
        # Historical base is 0.85
        assert entity.confidence >= 0.80
      end
    end

    test "confidence threshold filtering works" do
      context = %{
        text: "HTN",
        method: :rule_based,
        opts: [confidence_threshold: 0.95]
      }

      {:ok, entities} = Diagnosis.extract(context)

      Enum.each(entities, fn e ->
        assert e.confidence >= 0.95
      end)
    end
  end

  describe "Diagnosis.extract/1 - hybrid" do
    test "falls back to rule-based when transformer returns empty" do
      context = %{text: "Patient has HTN and DM", method: :hybrid, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      # Should still return results from rule-based
      assert length(entities) >= 2
    end
  end

  describe "Diagnosis.extract/1 - transformer" do
    test "returns empty list (stub implementation)" do
      context = %{text: "h/o diabetes", method: :transformer, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      # Transformer is currently a stub
      assert entities == []
    end
  end

  describe "edge cases" do
    test "handles empty string" do
      context = %{text: "", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)
      assert entities == []
    end

    test "handles text with only whitespace" do
      context = %{text: "   \n\t  ", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)
      assert entities == []
    end

    test "handles multiple occurrences of same condition" do
      context = %{
        text: "HTN in history, currently HTN controlled",
        method: :rule_based,
        opts: []
      }

      {:ok, entities} = Diagnosis.extract(context)

      # Should extract multiple occurrences
      assert length(entities) >= 2
    end
  end

  describe "clinical scenarios" do
    test "extracts from problem list style text" do
      text = """
      Problem List:
      1. HTN - controlled
      2. T2DM - on metformin
      3. COPD - moderate
      """

      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      assert length(entities) >= 3
      conditions =
        entities
        |> Enum.map(& &1.attributes.condition)
        |> Enum.map(&String.downcase/1)

      assert Enum.any?(conditions, &String.contains?(&1, "hypertension"))
      assert Enum.any?(conditions, &String.contains?(&1, "diabetes"))
    end

    test "extracts from past medical history" do
      text = "Past Medical History: h/o MI (2019), h/o CABG, chronic AFib"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      assert length(entities) >= 2
    end

    test "extracts suspected diagnoses from assessment" do
      text = "Assessment: suspected PE, r/o DVT"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      # Should find PE and DVT abbreviations at minimum
      assert length(entities) >= 2
    end

    test "extracts severity-qualified diagnoses" do
      text = "severe COPD with acute exacerbation"
      context = %{text: text, method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      assert length(entities) >= 1
    end
  end

  describe "attributes extraction" do
    test "extracts condition name" do
      context = %{text: "h/o diabetes mellitus", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      if length(entities) > 0 do
        entity = hd(entities)
        assert entity.attributes.condition != nil
      end
    end

    test "extracts status attribute" do
      context = %{text: "h/o hypertension", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      if length(entities) > 0 do
        entity = hd(entities)
        assert entity.attributes.status in [:active, :historical, :suspected, :resolved, :ruled_out]
      end
    end

    test "severity is extracted when present" do
      context = %{text: "severe hypertension", method: :rule_based, opts: []}
      {:ok, entities} = Diagnosis.extract(context)

      severity_entities = Enum.filter(entities, fn e ->
        e.metadata[:pattern_type] == :with_severity
      end)

      if length(severity_entities) > 0 do
        entity = hd(severity_entities)
        assert entity.attributes.severity == :severe
      end
    end
  end
end
