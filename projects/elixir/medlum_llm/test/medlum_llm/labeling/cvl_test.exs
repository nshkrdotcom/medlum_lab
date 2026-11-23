defmodule MedlumLlm.Labeling.CVLTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Labeling.CVL

  describe "agent_types/0" do
    test "returns all agent types" do
      types = CVL.agent_types()
      assert types == [:medication, :lab, :ontology, :temporal, :differential]
    end
  end

  describe "valid_agent_type?/1" do
    test "returns true for valid agent types" do
      for type <- [:medication, :lab, :ontology, :temporal, :differential] do
        assert CVL.valid_agent_type?(type)
      end
    end

    test "returns false for invalid agent types" do
      refute CVL.valid_agent_type?(:unknown)
      refute CVL.valid_agent_type?(:radiology)
    end

    test "returns false for non-atom input" do
      refute CVL.valid_agent_type?("medication")
      refute CVL.valid_agent_type?(nil)
    end
  end

  describe "consensus_methods/0" do
    test "returns all consensus methods" do
      methods = CVL.consensus_methods()
      assert methods == [:majority_vote, :weighted_vote, :unanimous]
    end
  end

  describe "valid_consensus_method?/1" do
    test "returns true for valid methods" do
      for method <- [:majority_vote, :weighted_vote, :unanimous] do
        assert CVL.valid_consensus_method?(method)
      end
    end

    test "returns false for invalid methods" do
      refute CVL.valid_consensus_method?(:random)
      refute CVL.valid_consensus_method?(:average)
    end
  end

  describe "validate_agent_verdict/1" do
    test "validates correct agent verdict" do
      verdict = %{
        verdict: :contradiction,
        confidence: 0.92,
        evidence: ["Dose mismatch: 500mg vs 1000mg"],
        ontology_codes: ["861004"]
      }

      assert {:ok, validated} = CVL.validate_agent_verdict(verdict)
      assert validated.verdict == :contradiction
      assert validated.confidence == 0.92
      assert validated.evidence == ["Dose mismatch: 500mg vs 1000mg"]
      assert validated.ontology_codes == ["861004"]
    end

    test "validates verdict with empty lists" do
      verdict = %{
        verdict: :entailment,
        confidence: 0.5,
        evidence: [],
        ontology_codes: []
      }

      assert {:ok, validated} = CVL.validate_agent_verdict(verdict)
      assert validated.evidence == []
      assert validated.ontology_codes == []
    end

    test "validates verdict with integer confidence" do
      verdict = %{
        verdict: :neutral,
        confidence: 1,
        evidence: [],
        ontology_codes: []
      }

      assert {:ok, validated} = CVL.validate_agent_verdict(verdict)
      assert validated.confidence == 1.0
    end

    test "returns error for missing verdict" do
      assert {:error, :missing_verdict} =
               CVL.validate_agent_verdict(%{
                 confidence: 0.5,
                 evidence: [],
                 ontology_codes: []
               })
    end

    test "returns error for invalid verdict" do
      assert {:error, {:invalid_verdict, :unknown}} =
               CVL.validate_agent_verdict(%{
                 verdict: :unknown,
                 confidence: 0.5,
                 evidence: [],
                 ontology_codes: []
               })
    end

    test "returns error for missing confidence" do
      assert {:error, :missing_confidence} =
               CVL.validate_agent_verdict(%{
                 verdict: :entailment,
                 evidence: [],
                 ontology_codes: []
               })
    end

    test "returns error for confidence out of range" do
      assert {:error, {:confidence_out_of_range, 1.5}} =
               CVL.validate_agent_verdict(%{
                 verdict: :entailment,
                 confidence: 1.5,
                 evidence: [],
                 ontology_codes: []
               })

      assert {:error, {:confidence_out_of_range, -0.1}} =
               CVL.validate_agent_verdict(%{
                 verdict: :entailment,
                 confidence: -0.1,
                 evidence: [],
                 ontology_codes: []
               })
    end

    test "returns error for missing evidence" do
      assert {:error, :missing_evidence} =
               CVL.validate_agent_verdict(%{
                 verdict: :entailment,
                 confidence: 0.5,
                 ontology_codes: []
               })
    end

    test "returns error for non-string evidence items" do
      assert {:error, :evidence_not_string_list} =
               CVL.validate_agent_verdict(%{
                 verdict: :entailment,
                 confidence: 0.5,
                 evidence: [123, "valid"],
                 ontology_codes: []
               })
    end

    test "returns error for missing ontology_codes" do
      assert {:error, :missing_ontology_codes} =
               CVL.validate_agent_verdict(%{
                 verdict: :entailment,
                 confidence: 0.5,
                 evidence: []
               })
    end

    test "returns error for non-map input" do
      assert {:error, :not_a_map} = CVL.validate_agent_verdict("not a map")
    end
  end

  describe "validate_agent_verdict!/1" do
    test "returns validated verdict for valid input" do
      verdict = %{
        verdict: :entailment,
        confidence: 0.85,
        evidence: [],
        ontology_codes: []
      }

      assert validated = CVL.validate_agent_verdict!(verdict)
      assert validated.verdict == :entailment
    end

    test "raises ArgumentError for invalid input" do
      assert_raise ArgumentError, ~r/Invalid agent verdict/, fn ->
        CVL.validate_agent_verdict!(%{verdict: :unknown})
      end
    end
  end

  describe "validate_consensus_result/1" do
    test "validates correct consensus result" do
      result = %{
        agent_verdicts: %{
          medication: %{
            verdict: :contradiction,
            confidence: 0.92,
            evidence: ["Dose mismatch"],
            ontology_codes: ["861004"]
          },
          lab: %{
            verdict: :entailment,
            confidence: 0.88,
            evidence: [],
            ontology_codes: []
          }
        },
        consensus_verdict: :contradiction,
        consensus_method: :weighted_vote,
        dissent_count: 1
      }

      assert {:ok, validated} = CVL.validate_consensus_result(result)
      assert validated.consensus_verdict == :contradiction
      assert validated.consensus_method == :weighted_vote
      assert validated.dissent_count == 1
      assert Map.has_key?(validated.agent_verdicts, :medication)
      assert Map.has_key?(validated.agent_verdicts, :lab)
    end

    test "returns error for invalid agent type in verdicts" do
      result = %{
        agent_verdicts: %{
          invalid_agent: %{
            verdict: :entailment,
            confidence: 0.5,
            evidence: [],
            ontology_codes: []
          }
        },
        consensus_verdict: :entailment,
        consensus_method: :majority_vote,
        dissent_count: 0
      }

      assert {:error, {:invalid_agent_type, :invalid_agent}} =
               CVL.validate_consensus_result(result)
    end

    test "returns error for invalid consensus method" do
      result = %{
        agent_verdicts: %{},
        consensus_verdict: :entailment,
        consensus_method: :invalid,
        dissent_count: 0
      }

      assert {:error, {:invalid_consensus_method, :invalid}} =
               CVL.validate_consensus_result(result)
    end

    test "returns error for negative dissent count" do
      result = %{
        agent_verdicts: %{},
        consensus_verdict: :entailment,
        consensus_method: :majority_vote,
        dissent_count: -1
      }

      assert {:error, {:invalid_dissent_count, -1}} =
               CVL.validate_consensus_result(result)
    end
  end
end
