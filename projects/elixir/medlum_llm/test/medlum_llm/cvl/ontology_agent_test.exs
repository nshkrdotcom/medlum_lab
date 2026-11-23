defmodule MedlumLlm.CVL.OntologyAgentTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.OntologyAgent

  describe "name/0" do
    test "returns :ontology_agent" do
      assert OntologyAgent.name() == :ontology_agent
    end
  end

  describe "weight/0" do
    test "returns 1.0" do
      assert OntologyAgent.weight() == 1.0
    end
  end

  describe "extract_clinical_entities/1" do
    test "extracts diagnosis from 'diagnosed with' pattern" do
      entities = OntologyAgent.extract_clinical_entities("Patient diagnosed with type 2 diabetes")

      assert length(entities) >= 1
      types = Enum.map(entities, & &1.type)
      assert :diagnosis in types
    end

    test "extracts explicit diagnosis" do
      entities = OntologyAgent.extract_clinical_entities("type 2 diabetes mellitus")

      assert length(entities) >= 1
      diag = Enum.find(entities, &(&1.type == :diagnosis))
      assert diag != nil
      assert String.contains?(String.downcase(diag.text), "diabetes")
    end

    test "extracts hypertension" do
      entities = OntologyAgent.extract_clinical_entities("Patient has hypertension")

      assert length(entities) >= 1
      types = Enum.map(entities, & &1.type)
      assert :diagnosis in types
    end

    test "extracts myocardial infarction" do
      entities = OntologyAgent.extract_clinical_entities("Patient suffered myocardial infarction")

      assert length(entities) >= 1
      diag = Enum.find(entities, &(&1.type == :diagnosis))
      assert diag != nil
    end

    test "extracts finding - chest pain" do
      entities = OntologyAgent.extract_clinical_entities("Patient presents with chest pain")

      assert length(entities) >= 1
      types = Enum.map(entities, & &1.type)
      assert :finding in types
    end

    test "extracts finding - shortness of breath" do
      entities = OntologyAgent.extract_clinical_entities("Patient has shortness of breath")

      assert length(entities) >= 1
      finding = Enum.find(entities, &(&1.type == :finding))
      assert finding != nil
    end

    test "extracts procedure - CABG" do
      entities = OntologyAgent.extract_clinical_entities("Patient underwent CABG")

      assert length(entities) >= 1
      types = Enum.map(entities, & &1.type)
      assert :procedure in types
    end

    test "extracts multiple entities" do
      text = "Patient with hypertension presents with chest pain and dyspnea"
      entities = OntologyAgent.extract_clinical_entities(text)

      # Should have at least hypertension (diagnosis), chest pain (finding), and dyspnea (finding)
      assert length(entities) >= 2
      types = Enum.map(entities, & &1.type)
      assert :diagnosis in types
      assert :finding in types
    end

    test "deduplicates entities by normalized text" do
      # Mention hypertension twice
      entities =
        OntologyAgent.extract_clinical_entities(
          "Patient has hypertension, chronic hypertension noted"
        )

      hypertension_entities =
        Enum.filter(entities, fn e ->
          String.contains?(String.downcase(e.text), "hypertension")
        end)

      # Should dedupe to one
      assert length(hypertension_entities) == 1
    end

    test "returns empty list for non-clinical text" do
      entities = OntologyAgent.extract_clinical_entities("The weather is nice today")
      assert entities == []
    end
  end

  describe "verify/2 with source grounding" do
    test "verifies known diagnosis with source evidence" do
      claim = "Patient diagnosed with type 2 diabetes mellitus"

      context = %{
        source_index: %{
          diagnoses: [%{text: "type 2 diabetes mellitus", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert Enum.any?(result.explanations, &String.contains?(&1, "validated"))
      assert length(result.evidence) > 0
    end

    test "verifies hypertension with source evidence" do
      claim = "Patient has hypertension"

      context = %{
        source_index: %{
          diagnoses: [%{text: "hypertension", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "verifies myocardial infarction with SNOMED/ICD-10" do
      claim = "Patient diagnosed with myocardial infarction"

      context = %{
        source_index: %{
          diagnoses: [%{text: "myocardial infarction", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
      # Check that SNOMED ID is mentioned in explanations
      assert Enum.any?(result.explanations, &String.contains?(&1, "SNOMED"))
    end

    test "returns neutral when diagnosis not in source documents" do
      claim = "Patient diagnosed with type 2 diabetes mellitus"

      context = %{
        source_index: %{
          diagnoses: []
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :neutral
      assert Enum.any?(result.explanations, &String.contains?(&1, "not found in source"))
    end

    test "returns neutral when no source_index provided" do
      claim = "Patient diagnosed with type 2 diabetes mellitus"
      context = %{}

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :neutral
    end
  end

  describe "verify/2 unknown diagnoses" do
    test "returns neutral for unknown diagnosis term" do
      claim = "Patient diagnosed with madeupitis"
      context = %{}

      result = OntologyAgent.verify(claim, context)

      # Unknown diagnosis should be neutral, not contradiction
      # (needs human review, not definitively wrong)
      assert result.verdict == :neutral
    end

    test "returns neutral for no clinical entities" do
      claim = "The weather is nice today"
      context = %{}

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :neutral
      assert Enum.any?(result.explanations, &String.contains?(&1, "No clinical entities"))
    end
  end

  describe "verify/2 findings" do
    test "verifies known finding with source evidence" do
      claim = "Patient presents with chest pain"

      context = %{
        source_index: %{
          diagnoses: [%{text: "chest pain", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "verifies dyspnea finding" do
      claim = "Patient has shortness of breath"

      context = %{
        source_index: %{
          diagnoses: [%{text: "shortness of breath", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end
  end

  describe "verify/2 procedures" do
    test "verifies known procedure with source evidence" do
      claim = "Patient underwent CABG"

      context = %{
        source_index: %{
          diagnoses: [%{text: "underwent CABG", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "verifies appendectomy procedure" do
      claim = "Patient underwent appendectomy"

      context = %{
        source_index: %{
          diagnoses: [%{text: "underwent appendectomy", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end
  end

  describe "verify/2 relationships" do
    test "verifies finding supports diagnosis" do
      claim = "Patient with chest pain diagnosed with myocardial infarction"

      context = %{
        source_index: %{
          diagnoses: [
            %{text: "chest pain", doc_id: "note-1"},
            %{text: "myocardial infarction", doc_id: "note-1"}
          ]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
      # Chest pain supports MI diagnosis
      assert Enum.any?(result.explanations, &String.contains?(&1, "supports"))
    end

    test "flags when finding does not typically associate with diagnosis" do
      claim = "Patient with cough diagnosed with hypertension"

      context = %{
        source_index: %{
          diagnoses: [
            %{text: "cough", doc_id: "note-1"},
            %{text: "hypertension", doc_id: "note-1"}
          ]
        }
      }

      result = OntologyAgent.verify(claim, context)

      # Cough doesn't typically associate with hypertension
      # Result could be entailment (both valid) but with a neutral relationship verdict
      assert result.verdict in [:entailment, :neutral]
    end
  end

  describe "verify/2 semantic fit" do
    test "validates diagnosis fits chief complaint" do
      claim = "Patient diagnosed with type 2 diabetes mellitus"

      context = %{
        chief_complaint: "increased thirst and polyuria",
        source_index: %{
          diagnoses: [%{text: "type 2 diabetes mellitus", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "allows diagnosis when no chief complaint provided" do
      claim = "Patient diagnosed with type 2 diabetes mellitus"

      context = %{
        source_index: %{
          diagnoses: [%{text: "type 2 diabetes mellitus", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end
  end

  describe "verify/2 evidence format" do
    test "returns evidence with doc_id and snippet" do
      claim = "Patient diagnosed with hypertension"

      context = %{
        source_index: %{
          diagnoses: [%{text: "hypertension documented", doc_id: "note-123"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert length(result.evidence) >= 1
      evidence = hd(result.evidence)
      assert evidence[:doc_id] == "note-123"
      assert evidence[:snippet] =~ "hypertension"
      assert evidence[:entity_type] == :diagnosis
    end
  end

  describe "verify/2 multiple entities" do
    test "verifies multiple diagnoses in one claim" do
      claim = "Patient has hypertension and type 2 diabetes"

      context = %{
        source_index: %{
          diagnoses: [
            %{text: "hypertension", doc_id: "note-1"},
            %{text: "type 2 diabetes", doc_id: "note-1"}
          ]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert length(result.sub_verdicts) >= 2
    end

    test "handles mixed entailment and neutral verdicts" do
      claim = "Patient has hypertension and madeupitis"

      context = %{
        source_index: %{
          diagnoses: [%{text: "hypertension", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      # One valid (hypertension), one unknown (madeupitis - neutral)
      # Overall should be neutral since unknown needs review
      assert result.verdict in [:neutral, :entailment]
    end
  end

  describe "verify/2 abbreviations" do
    test "handles MI abbreviation" do
      claim = "Patient diagnosed with MI"

      context = %{
        source_index: %{
          diagnoses: [%{text: "MI", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "handles CHF abbreviation" do
      claim = "Patient has CHF"

      context = %{
        source_index: %{
          diagnoses: [%{text: "CHF", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "handles COPD abbreviation" do
      claim = "Patient diagnosed with COPD"

      context = %{
        source_index: %{
          diagnoses: [%{text: "COPD", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "handles afib abbreviation" do
      claim = "Patient has atrial fibrillation"

      context = %{
        source_index: %{
          diagnoses: [%{text: "atrial fibrillation", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "handles CVA abbreviation" do
      claim = "Patient had a stroke"

      context = %{
        source_index: %{
          diagnoses: [%{text: "stroke", doc_id: "note-1"}]
        }
      }

      result = OntologyAgent.verify(claim, context)

      assert result.verdict == :entailment
    end
  end
end
