defmodule MedlumLlm.CVL.LabAgentTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.LabAgent

  describe "name/0" do
    test "returns :lab_agent" do
      assert LabAgent.name() == :lab_agent
    end
  end

  describe "weight/0" do
    test "returns 1.2" do
      assert LabAgent.weight() == 1.2
    end
  end

  describe "extract_lab_values/1" do
    test "extracts HbA1c" do
      labs = LabAgent.extract_lab_values("HbA1c is 7.2%")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "hemoglobin_a1c"
      assert lab.value == 7.2
    end

    test "extracts A1c variant" do
      labs = LabAgent.extract_lab_values("A1c 6.5%")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "hemoglobin_a1c"
      assert lab.value == 6.5
    end

    test "extracts glucose" do
      labs = LabAgent.extract_lab_values("Fasting glucose 120 mg/dL")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "glucose"
      assert lab.value == 120.0
    end

    test "extracts hemoglobin" do
      labs = LabAgent.extract_lab_values("Hgb 12.5 g/dL")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "hemoglobin"
      assert lab.value == 12.5
    end

    test "extracts WBC" do
      labs = LabAgent.extract_lab_values("WBC 8.5 K/uL")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "wbc"
      assert lab.value == 8.5
    end

    test "extracts creatinine" do
      labs = LabAgent.extract_lab_values("creatinine 1.2 mg/dL")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "creatinine"
      assert lab.value == 1.2
    end

    test "extracts potassium" do
      labs = LabAgent.extract_lab_values("Potassium 4.2 mEq/L")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "potassium"
      assert lab.value == 4.2
    end

    test "extracts sodium" do
      labs = LabAgent.extract_lab_values("sodium 140 mEq/L")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "sodium"
      assert lab.value == 140.0
    end

    test "extracts platelets" do
      labs = LabAgent.extract_lab_values("platelets 250 K/uL")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "platelets"
      assert lab.value == 250.0
    end

    test "extracts INR" do
      labs = LabAgent.extract_lab_values("INR 2.5")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "inr"
      assert lab.value == 2.5
    end

    test "extracts eGFR" do
      labs = LabAgent.extract_lab_values("eGFR 65 mL/min")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "egfr"
      assert lab.value == 65.0
    end

    test "extracts cholesterol values" do
      labs = LabAgent.extract_lab_values("Total cholesterol 220 mg/dL, LDL 130 mg/dL, HDL 45 mg/dL")

      assert length(labs) == 3
      names = Enum.map(labs, & &1.test_name)
      assert "cholesterol_total" in names
      assert "ldl_cholesterol" in names
      assert "hdl_cholesterol" in names
    end

    test "extracts TSH" do
      labs = LabAgent.extract_lab_values("TSH 2.5 mIU/L")

      assert length(labs) == 1
      lab = hd(labs)
      assert lab.test_name == "tsh"
      assert lab.value == 2.5
    end

    test "extracts multiple labs" do
      text = "Labs show hemoglobin 12.5 g/dL, WBC 8.5 K/uL, and platelets 250 K/uL"
      labs = LabAgent.extract_lab_values(text)

      assert length(labs) == 3
      names = Enum.map(labs, & &1.test_name)
      assert "hemoglobin" in names
      assert "wbc" in names
      assert "platelets" in names
    end

    test "returns empty list when no labs found" do
      labs = LabAgent.extract_lab_values("Patient has chest pain")
      assert labs == []
    end
  end

  describe "verify/2 with source grounding" do
    test "verifies normal lab value with source evidence" do
      claim = "Patient's HbA1c is 5.4%"
      context = %{
        source_index: %{
          labs: [%{text: "HbA1c 5.4%", doc_id: "lab-1"}]
        }
      }

      result = LabAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert hd(result.explanations) =~ "normal"
      assert length(result.evidence) == 1
      assert hd(result.evidence).doc_id == "lab-1"
    end

    test "verifies high but valid lab value with source evidence" do
      claim = "HbA1c is 8.5%"
      context = %{
        source_index: %{
          labs: [%{text: "hemoglobin_a1c 8.5%", doc_id: "lab-1"}]
        }
      }

      result = LabAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert hd(result.explanations) =~ "high"
    end

    test "verifies low but valid lab value with source evidence" do
      claim = "Hemoglobin is 10 g/dL"
      context = %{
        source_index: %{
          labs: [%{text: "hemoglobin 10 g/dL", doc_id: "lab-1"}]
        }
      }

      result = LabAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert hd(result.explanations) =~ "low"
    end

    test "returns neutral when lab not in source documents" do
      claim = "HbA1c is 5.4%"
      context = %{
        source_index: %{
          labs: []
        }
      }

      result = LabAgent.verify(claim, context)

      assert result.verdict == :neutral
      assert hd(result.explanations) =~ "not found in source"
    end

    test "returns neutral when no source_index provided" do
      claim = "HbA1c is 5.4%"
      context = %{}

      result = LabAgent.verify(claim, context)

      assert result.verdict == :neutral
      assert hd(result.explanations) =~ "not found in source"
    end
  end

  describe "verify/2 physiological validation" do
    test "flags physiologically impossible value" do
      claim = "Hemoglobin is 50 g/dL"
      context = %{}

      result = LabAgent.verify(claim, context)

      assert result.verdict == :contradiction
      assert hd(result.explanations) =~ "Impossible"
    end

    test "flags impossible HbA1c" do
      claim = "HbA1c is 25%"
      context = %{}

      result = LabAgent.verify(claim, context)

      assert result.verdict == :contradiction
    end

    test "flags impossible potassium (too high)" do
      claim = "Potassium 15 mEq/L"
      context = %{}

      result = LabAgent.verify(claim, context)

      assert result.verdict == :contradiction
    end

    test "flags impossible sodium (too low)" do
      claim = "Sodium 50 mEq/L"
      context = %{}

      result = LabAgent.verify(claim, context)

      assert result.verdict == :contradiction
    end
  end

  describe "verify/2 unknown labs" do
    test "returns neutral for unknown lab" do
      claim = "The frobnicator level is 42"
      context = %{}

      result = LabAgent.verify(claim, context)

      assert result.verdict == :neutral
    end

    test "returns neutral when no labs found" do
      claim = "Patient has chest pain"
      context = %{}

      result = LabAgent.verify(claim, context)

      assert result.verdict == :neutral
      assert hd(result.explanations) =~ "No lab values found"
    end
  end

  describe "verify/2 with demographics" do
    test "accepts demographics in context" do
      claim = "Hemoglobin 14 g/dL"
      context = %{
        demographics: %{age: 55, sex: :male},
        source_index: %{
          labs: [%{text: "hemoglobin 14", doc_id: "lab-1"}]
        }
      }

      result = LabAgent.verify(claim, context)

      assert result.verdict == :entailment
    end
  end

  describe "verify/2 critical values" do
    test "identifies critical high glucose" do
      claim = "Glucose 450 mg/dL"
      context = %{
        source_index: %{
          labs: [%{text: "glucose 450", doc_id: "lab-1"}]
        }
      }

      result = LabAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert hd(result.explanations) =~ "critical_high"
    end

    test "identifies critical low potassium" do
      claim = "Potassium 2.0 mEq/L"
      context = %{
        source_index: %{
          labs: [%{text: "potassium 2.0", doc_id: "lab-1"}]
        }
      }

      result = LabAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert hd(result.explanations) =~ "critical_low"
    end
  end

  describe "verify/2 reference range reporting" do
    test "includes reference range in explanation" do
      claim = "HbA1c is 7.2%"
      context = %{
        source_index: %{
          labs: [%{text: "HbA1c 7.2%", doc_id: "lab-1"}]
        }
      }

      result = LabAgent.verify(claim, context)

      explanation = hd(result.explanations)
      assert explanation =~ "ref:"
      assert explanation =~ "4.0-5.6"
    end
  end

  describe "verify/2 multiple labs" do
    test "verifies multiple labs in one claim" do
      claim = "Labs: Hemoglobin 13 g/dL, WBC 7.5 K/uL"
      context = %{
        source_index: %{
          labs: [
            %{text: "hemoglobin 13", doc_id: "lab-1"},
            %{text: "WBC 7.5", doc_id: "lab-1"}
          ]
        }
      }

      result = LabAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert length(result.sub_verdicts) == 2
      assert length(result.evidence) == 2
    end

    test "contradiction takes precedence over entailment" do
      claim = "Labs: Hemoglobin 13 g/dL, Sodium 50 mEq/L"
      context = %{
        source_index: %{
          labs: [
            %{text: "hemoglobin 13", doc_id: "lab-1"},
            %{text: "sodium 50", doc_id: "lab-1"}
          ]
        }
      }

      result = LabAgent.verify(claim, context)

      # Sodium 50 is physiologically impossible
      assert result.verdict == :contradiction
    end
  end
end
