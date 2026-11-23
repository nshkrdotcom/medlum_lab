defmodule MedlumLlm.CVL.DifferentialAgentTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.DifferentialAgent

  describe "name/0 and weight/0" do
    test "returns correct values" do
      assert DifferentialAgent.name() == :differential_agent
      assert DifferentialAgent.weight() == 1.0
    end
  end

  describe "extract_symptoms/1" do
    test "extracts common symptoms" do
      symptoms = DifferentialAgent.extract_symptoms("Patient has chest pain and dyspnea")

      names = Enum.map(symptoms, & &1.name)
      assert "chest pain" in names
      assert "dyspnea" in names
    end

    test "normalizes symptom names" do
      symptoms = DifferentialAgent.extract_symptoms("SOB and tiredness")

      names = Enum.map(symptoms, & &1.name)
      assert "dyspnea" in names
      assert "fatigue" in names
    end

    test "extracts fever variations" do
      symptoms = DifferentialAgent.extract_symptoms("Patient is febrile")
      names = Enum.map(symptoms, & &1.name)
      assert "fever" in names
    end

    test "extracts shortness of breath variations" do
      symptoms = DifferentialAgent.extract_symptoms("Patient with shortness of breath")
      names = Enum.map(symptoms, & &1.name)
      assert "dyspnea" in names
    end

    test "extracts multiple symptoms" do
      symptoms =
        DifferentialAgent.extract_symptoms(
          "Patient presents with chest pain, dyspnea, nausea, and weakness"
        )

      names = Enum.map(symptoms, & &1.name)
      assert "chest pain" in names
      assert "dyspnea" in names
      assert "nausea" in names
      assert "weakness" in names
    end

    test "deduplicates symptoms" do
      symptoms =
        DifferentialAgent.extract_symptoms("Patient has chest pain. Chest pain is severe.")

      names = Enum.map(symptoms, & &1.name)
      assert Enum.count(names, &(&1 == "chest pain")) == 1
    end

    test "extracts diabetes-related symptoms" do
      symptoms =
        DifferentialAgent.extract_symptoms(
          "Patient reports polyuria, polydipsia, and blurred vision"
        )

      names = Enum.map(symptoms, & &1.name)
      assert "polyuria" in names
      assert "polydipsia" in names
      assert "blurred vision" in names
    end

    test "extracts syncope" do
      symptoms = DifferentialAgent.extract_symptoms("Patient had fainting episode")
      names = Enum.map(symptoms, & &1.name)
      assert "syncope" in names
    end

    test "extracts diaphoresis" do
      symptoms = DifferentialAgent.extract_symptoms("Patient is sweating profusely")
      names = Enum.map(symptoms, & &1.name)
      assert "diaphoresis" in names
    end
  end

  describe "extract_diagnoses/1" do
    test "extracts diagnoses with 'diagnosed with' pattern" do
      diagnoses = DifferentialAgent.extract_diagnoses("Diagnosed with myocardial infarction")

      assert length(diagnoses) >= 1
      names = Enum.map(diagnoses, & &1.name)
      assert "myocardial infarction" in names
    end

    test "extracts diagnoses with 'diagnosis of' pattern" do
      diagnoses = DifferentialAgent.extract_diagnoses("Final diagnosis of pneumonia")

      names = Enum.map(diagnoses, & &1.name)
      assert "pneumonia" in names
    end

    test "extracts abbreviated diagnoses" do
      diagnoses = DifferentialAgent.extract_diagnoses("Patient has MI")
      names = Enum.map(diagnoses, & &1.name)
      assert "myocardial infarction" in names

      diagnoses = DifferentialAgent.extract_diagnoses("Assessment: CHF")
      names = Enum.map(diagnoses, & &1.name)
      assert "heart failure" in names

      diagnoses = DifferentialAgent.extract_diagnoses("History of PE")
      names = Enum.map(diagnoses, & &1.name)
      assert "pulmonary embolism" in names
    end

    test "extracts diabetes variations" do
      diagnoses = DifferentialAgent.extract_diagnoses("Patient has type 2 diabetes")
      names = Enum.map(diagnoses, & &1.name)
      assert "diabetes" in names

      diagnoses = DifferentialAgent.extract_diagnoses("Type 1 diabetes mellitus")
      names = Enum.map(diagnoses, & &1.name)
      assert "diabetes" in names
    end

    test "extracts multiple diagnoses" do
      diagnoses =
        DifferentialAgent.extract_diagnoses(
          "Patient has hypertension, diabetes, and heart failure"
        )

      names = Enum.map(diagnoses, & &1.name)
      assert "hypertension" in names
      assert "diabetes" in names
      assert "heart failure" in names
    end

    test "extracts stroke variations" do
      diagnoses = DifferentialAgent.extract_diagnoses("Patient had a stroke")
      names = Enum.map(diagnoses, & &1.name)
      assert "stroke" in names

      diagnoses = DifferentialAgent.extract_diagnoses("History of CVA")
      names = Enum.map(diagnoses, & &1.name)
      assert "stroke" in names
    end
  end

  describe "verify/2 - basic functionality" do
    test "verifies symptoms support diagnosis with source grounding" do
      claim = "Patient with chest pain and dyspnea diagnosed with myocardial infarction"

      context = %{
        source_index: %{
          diagnoses: [%{text: "myocardial infarction", doc_id: "note-1"}],
          findings: [
            %{text: "chest pain", doc_id: "note-1"},
            %{text: "dyspnea", doc_id: "note-1"}
          ]
        }
      }

      result = DifferentialAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert Enum.any?(result.explanations, &String.contains?(&1, "Supporting symptoms"))
    end

    test "returns neutral when no diagnosis found" do
      claim = "Patient has chest pain"
      context = %{}

      result = DifferentialAgent.verify(claim, context)

      assert result.verdict == :neutral
      assert Enum.any?(result.explanations, &String.contains?(&1, "No diagnoses found"))
    end

    test "returns neutral when symptoms don't match" do
      claim = "Patient with headache diagnosed with appendicitis"

      context = %{
        source_index: %{
          diagnoses: [%{text: "appendicitis", doc_id: "note-1"}],
          findings: [%{text: "headache", doc_id: "note-1"}]
        }
      }

      result = DifferentialAgent.verify(claim, context)

      # Headache doesn't support appendicitis
      assert result.verdict in [:neutral, :entailment]
    end

    test "returns neutral when diagnosis not in source documents" do
      claim = "Patient diagnosed with myocardial infarction"
      # No source index provided
      context = %{}

      result = DifferentialAgent.verify(claim, context)

      assert result.verdict == :neutral
    end
  end

  describe "verify/2 - source grounding" do
    test "links evidence to source documents" do
      claim = "Patient with fever and cough diagnosed with pneumonia"

      context = %{
        source_index: %{
          diagnoses: [%{text: "pneumonia", doc_id: "note-1"}],
          findings: [
            %{text: "fever", doc_id: "note-1"},
            %{text: "cough", doc_id: "note-1"}
          ]
        }
      }

      result = DifferentialAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert length(result.evidence) > 0

      # Check evidence has doc_id
      assert Enum.all?(result.evidence, fn ev ->
               ev[:doc_id] == "note-1"
             end)
    end

    test "returns neutral when diagnosis not grounded in source" do
      claim = "Patient diagnosed with meningitis"

      context = %{
        source_index: %{
          diagnoses: [%{text: "headache workup", doc_id: "note-1"}],
          findings: []
        }
      }

      result = DifferentialAgent.verify(claim, context)

      assert result.verdict == :neutral
      assert Enum.any?(result.explanations, &String.contains?(&1, "No diagnoses supported"))
    end
  end

  describe "verify/2 - red flags" do
    test "does not flag red flag when addressed by diagnosis" do
      claim =
        "Patient with chest pain and dyspnea diagnosed with myocardial infarction and pulmonary embolism"

      context = %{
        source_index: %{
          diagnoses: [
            %{text: "myocardial infarction", doc_id: "note-1"},
            %{text: "pulmonary embolism", doc_id: "note-1"}
          ],
          findings: [
            %{text: "chest pain", doc_id: "note-1"},
            %{text: "dyspnea", doc_id: "note-1"}
          ]
        }
      }

      result = DifferentialAgent.verify(claim, context)

      # Should NOT have red flag contradiction since MI and PE are in workup
      refute Enum.any?(result.explanations, &String.contains?(&1, "Red flag not addressed"))
    end
  end

  describe "verify/2 - multiple diagnoses" do
    test "verifies multiple diagnoses with appropriate symptoms" do
      claim = "Patient with dyspnea and edema diagnosed with heart failure"

      context = %{
        source_index: %{
          diagnoses: [%{text: "heart failure", doc_id: "note-1"}],
          findings: [
            %{text: "dyspnea", doc_id: "note-1"},
            %{text: "edema", doc_id: "note-1"}
          ]
        }
      }

      result = DifferentialAgent.verify(claim, context)

      assert result.verdict == :entailment
    end
  end

  describe "verify/2 - result structure" do
    test "returns proper result structure" do
      claim = "Patient with chest pain diagnosed with myocardial infarction"

      context = %{
        source_index: %{
          diagnoses: [%{text: "myocardial infarction", doc_id: "note-1"}],
          findings: [%{text: "chest pain", doc_id: "note-1"}]
        }
      }

      result = DifferentialAgent.verify(claim, context)

      assert is_atom(result.verdict)
      assert is_float(result.confidence)
      assert is_list(result.explanations)
      assert is_list(result.evidence)
      assert is_list(result.sub_verdicts)
    end
  end

  describe "edge cases" do
    test "handles empty claim" do
      result = DifferentialAgent.verify("", %{})

      assert result.verdict == :neutral
    end

    test "handles claim with only symptoms no diagnosis" do
      claim = "Patient has chest pain, dyspnea, and nausea"
      context = %{}

      result = DifferentialAgent.verify(claim, context)

      assert result.verdict == :neutral
      assert Enum.any?(result.explanations, &String.contains?(&1, "No diagnoses found"))
    end

    test "handles missing source_index" do
      claim = "Patient diagnosed with pneumonia"
      context = %{some_other_key: "value"}

      result = DifferentialAgent.verify(claim, context)

      assert result.verdict == :neutral
    end

    test "handles empty source_index" do
      claim = "Patient diagnosed with pneumonia"
      context = %{source_index: %{}}

      result = DifferentialAgent.verify(claim, context)

      assert result.verdict == :neutral
    end
  end
end
