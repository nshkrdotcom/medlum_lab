defmodule MedlumLlm.CVL.MedicationAgentTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.MedicationAgent

  describe "name/0" do
    test "returns :medication_agent" do
      assert MedicationAgent.name() == :medication_agent
    end
  end

  describe "weight/0" do
    test "returns 1.5" do
      assert MedicationAgent.weight() == 1.5
    end
  end

  describe "extract_medications/1" do
    test "extracts medication names" do
      meds = MedicationAgent.extract_medications("Patient takes metformin 500mg twice daily")

      assert length(meds) == 1
      assert hd(meds).name == "metformin"
    end

    test "extracts multiple medications" do
      meds =
        MedicationAgent.extract_medications("Started on lisinopril 10mg and atorvastatin 40mg daily")

      assert length(meds) == 2
      names = Enum.map(meds, & &1.name)
      assert "lisinopril" in names
      assert "atorvastatin" in names
    end

    test "extracts dose and frequency" do
      meds = MedicationAgent.extract_medications("metformin 500mg twice daily")

      med = hd(meds)
      assert med.dose == 500.0
      assert med.unit == "mg"
      assert med.frequency == "twice_daily"
    end

    test "extracts medication without dose" do
      meds = MedicationAgent.extract_medications("Patient is on warfarin")

      assert length(meds) == 1
      med = hd(meds)
      assert med.name == "warfarin"
      assert is_nil(med.dose)
    end

    test "normalizes frequency aliases" do
      meds = MedicationAgent.extract_medications("metformin 500mg bid")

      med = hd(meds)
      assert med.frequency == "twice_daily"
    end

    test "deduplicates medications by name" do
      meds =
        MedicationAgent.extract_medications(
          "metformin 500mg daily, patient continues metformin therapy"
        )

      assert length(meds) == 1
    end
  end

  describe "verify/2" do
    test "verifies known medication with source evidence" do
      claim = "Patient started on metformin 500mg twice daily"

      context = %{
        conditions: [:diabetes],
        current_medications: [],
        source_index: %{
          medications: [%{text: "metformin 500mg BID", doc_id: "note-1"}]
        }
      }

      result = MedicationAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert result.confidence > 0.5
      assert length(result.evidence) > 0
    end

    test "flags unknown medication" do
      claim = "Patient started on madeupdrugxyz 100mg daily"
      context = %{}

      result = MedicationAgent.verify(claim, context)

      assert result.verdict == :contradiction
      assert hd(result.explanations) =~ "not found in RxNorm"
    end

    test "returns neutral when no medications" do
      claim = "Patient has chest pain"
      context = %{}

      result = MedicationAgent.verify(claim, context)

      assert result.verdict == :neutral
      assert hd(result.explanations) =~ "No medication mentions"
    end

    test "returns neutral when medication valid but not in source" do
      claim = "Patient started on metformin 500mg twice daily"
      # No source_index provided
      context = %{conditions: [:diabetes], current_medications: []}

      result = MedicationAgent.verify(claim, context)

      assert result.verdict == :neutral
      assert Enum.any?(result.explanations, &String.contains?(&1, "not found in source"))
    end

    test "flags contraindication" do
      claim = "Patient with renal failure started on metformin"

      context = %{
        conditions: ["renal_failure"],
        source_index: %{
          medications: [%{text: "metformin 500mg", doc_id: "note-1"}]
        }
      }

      result = MedicationAgent.verify(claim, context)

      assert result.verdict == :contradiction
      assert Enum.any?(result.explanations, &String.contains?(&1, "Contraindication"))
    end

    test "flags interaction" do
      claim = "Patient started on aspirin"

      context = %{
        current_medications: [%{name: "warfarin"}],
        source_index: %{
          medications: [%{text: "aspirin 81mg", doc_id: "note-1"}]
        }
      }

      result = MedicationAgent.verify(claim, context)

      # Interaction is neutral (warning) not contradiction
      assert result.verdict in [:neutral, :entailment]
      assert Enum.any?(result.explanations, &String.contains?(&1, "interaction"))
    end

    test "flags invalid dose" do
      claim = "Patient started on metformin 5000mg daily"

      context = %{
        source_index: %{
          medications: [%{text: "metformin 5000mg daily", doc_id: "note-1"}]
        }
      }

      result = MedicationAgent.verify(claim, context)

      assert result.verdict == :contradiction
      assert Enum.any?(result.explanations, &String.contains?(&1, "Invalid dose"))
    end

    test "accepts dose within therapeutic range" do
      claim = "Patient on atorvastatin 40mg daily"

      context = %{
        source_index: %{
          medications: [%{text: "atorvastatin 40mg qd", doc_id: "note-1"}]
        }
      }

      result = MedicationAgent.verify(claim, context)

      assert result.verdict == :entailment
    end

    test "handles conditions as atoms" do
      claim = "Patient with liver disease started on atorvastatin"

      context = %{
        conditions: [:liver_disease],
        source_index: %{
          medications: [%{text: "atorvastatin 40mg", doc_id: "note-1"}]
        }
      }

      result = MedicationAgent.verify(claim, context)

      assert result.verdict == :contradiction
      assert Enum.any?(result.explanations, &String.contains?(&1, "Contraindication"))
    end

    test "handles conditions as maps" do
      claim = "Patient with bleeding disorder started on warfarin"

      context = %{
        conditions: [%{name: "bleeding_disorder"}],
        source_index: %{
          medications: [%{text: "warfarin 5mg", doc_id: "note-1"}]
        }
      }

      result = MedicationAgent.verify(claim, context)

      assert result.verdict == :contradiction
    end

    test "returns evidence with doc_id and snippet" do
      claim = "Patient on lisinopril 10mg daily"

      context = %{
        source_index: %{
          medications: [%{text: "lisinopril 10mg qd", doc_id: "note-123"}]
        }
      }

      result = MedicationAgent.verify(claim, context)

      assert length(result.evidence) == 1
      evidence = hd(result.evidence)
      assert evidence[:doc_id] == "note-123"
      assert evidence[:snippet] == "lisinopril 10mg qd"
      assert evidence[:entity_type] == :medication
    end

    test "multiple medications aggregates correctly" do
      claim = "Started on metformin 500mg and atorvastatin 40mg"

      context = %{
        source_index: %{
          medications: [
            %{text: "metformin 500mg", doc_id: "note-1"},
            %{text: "atorvastatin 40mg", doc_id: "note-1"}
          ]
        }
      }

      result = MedicationAgent.verify(claim, context)

      assert result.verdict == :entailment
      assert length(result.sub_verdicts) == 2
    end

    test "one invalid medication causes contradiction" do
      claim = "Started on metformin 500mg and fakemedicine 100mg"

      context = %{
        source_index: %{
          medications: [%{text: "metformin 500mg", doc_id: "note-1"}]
        }
      }

      result = MedicationAgent.verify(claim, context)

      # Contradiction takes precedence
      assert result.verdict == :contradiction
    end
  end
end
