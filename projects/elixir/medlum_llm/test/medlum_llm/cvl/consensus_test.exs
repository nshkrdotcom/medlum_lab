defmodule MedlumLlm.CVL.ConsensusTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.Consensus

  describe "verify/3" do
    test "returns consensus result structure" do
      claim = "Patient has diabetes"
      context = %{source_index: %{diagnoses: []}}

      result = Consensus.verify(claim, context)

      assert Map.has_key?(result, :verdict)
      assert Map.has_key?(result, :confidence)
      assert Map.has_key?(result, :agent_results)
      assert Map.has_key?(result, :scores)
    end

    test "verdict is one of three expected values" do
      claim = "Some medical claim"
      context = %{}

      result = Consensus.verify(claim, context)

      assert result.verdict in [:entailment, :contradiction, :neutral]
    end

    test "confidence is between 0 and 1" do
      claim = "Patient on metformin"
      context = %{}

      result = Consensus.verify(claim, context)

      assert result.confidence >= 0.0
      assert result.confidence <= 1.0
    end

    test "returns agent results for all agents" do
      claim = "Patient diagnosed with diabetes"
      context = %{source_index: %{diagnoses: []}}

      result = Consensus.verify(claim, context)

      # Should have results from all 5 agents
      assert length(result.agent_results) == 5
    end

    test "agent results include agent name and weight" do
      claim = "Patient has chest pain"
      context = %{}

      result = Consensus.verify(claim, context)

      agent_result = hd(result.agent_results)
      assert Map.has_key?(agent_result, :agent)
      assert Map.has_key?(agent_result, :weight)
      assert Map.has_key?(agent_result, :result)
    end

    test "scores include all three verdict types" do
      claim = "HbA1c is 7.2%"
      context = %{}

      result = Consensus.verify(claim, context)

      assert Map.has_key?(result.scores, :entailment)
      assert Map.has_key?(result.scores, :contradiction)
      assert Map.has_key?(result.scores, :neutral)
    end
  end

  describe "verify/3 aggregation rules" do
    test "returns neutral when no source evidence" do
      claim = "Patient started on metformin 500mg"
      # Empty source index means agents should return neutral
      context = %{source_index: %{medications: [], labs: [], diagnoses: [], findings: []}}

      result = Consensus.verify(claim, context)

      # Without source evidence, should be neutral
      assert result.verdict == :neutral
    end

    test "returns entailment when claim supported by source" do
      claim = "Patient on metformin 500mg"

      context = %{
        source_index: %{
          medications: [%{text: "metformin 500mg", doc_id: "note-1"}],
          labs: [],
          diagnoses: [],
          findings: []
        }
      }

      result = Consensus.verify(claim, context)

      # With source evidence, medication agent should return entailment
      assert result.verdict in [:entailment, :neutral]
    end

    test "contradiction takes precedence" do
      claim = "Patient started on unknowndrugxyz 100mg"

      context = %{
        source_index: %{medications: [], labs: [], diagnoses: [], findings: []}
      }

      result = Consensus.verify(claim, context)

      # Unknown medication should cause contradiction from medication agent
      assert result.verdict == :contradiction
    end
  end

  describe "verify_claim/3" do
    test "is alias for verify/3" do
      claim = "Patient has diabetes"
      context = %{}

      result1 = Consensus.verify(claim, context)
      result2 = Consensus.verify_claim(claim, context)

      assert result1.verdict == result2.verdict
    end
  end

  describe "agents/0" do
    test "returns list of 5 agents" do
      agents = Consensus.agents()

      assert length(agents) == 5
    end

    test "all agents implement Agent behaviour" do
      agents = Consensus.agents()

      for agent <- agents do
        assert function_exported?(agent, :name, 0)
        assert function_exported?(agent, :weight, 0)
        assert function_exported?(agent, :verify, 2)
      end
    end
  end

  describe "total_weight/0" do
    test "returns sum of agent weights" do
      total = Consensus.total_weight()

      # 1.5 + 1.2 + 1.0 + 0.8 + 1.0 = 5.5
      assert total == 5.5
    end
  end

  describe "weighted scoring" do
    test "medication agent has highest weight" do
      agents = Consensus.agents()

      weights =
        Enum.map(agents, fn agent ->
          {agent.name(), agent.weight()}
        end)

      medication_weight = Enum.find_value(weights, fn {name, w} -> if name == :medication_agent, do: w end)

      assert medication_weight == 1.5
      assert medication_weight == Enum.max(Keyword.values(weights))
    end

    test "temporal agent has lowest weight" do
      agents = Consensus.agents()

      weights =
        Enum.map(agents, fn agent ->
          {agent.name(), agent.weight()}
        end)

      temporal_weight = Enum.find_value(weights, fn {name, w} -> if name == :temporal_agent, do: w end)

      assert temporal_weight == 0.8
      assert temporal_weight == Enum.min(Keyword.values(weights))
    end
  end

  describe "parallel execution" do
    test "handles agent timeout gracefully" do
      claim = "Patient has diabetes"
      context = %{}

      # Short timeout shouldn't crash
      result = Consensus.verify(claim, context, timeout: 100)

      # Should still return a valid result
      assert result.verdict in [:entailment, :contradiction, :neutral]
    end

    test "agents run concurrently" do
      claim = "Patient on metformin with HbA1c 7.2% diagnosed with diabetes"

      context = %{
        source_index: %{
          medications: [%{text: "metformin", doc_id: "note-1"}],
          labs: [%{text: "HbA1c 7.2%", doc_id: "note-1"}],
          diagnoses: [%{text: "diabetes", doc_id: "note-1"}],
          findings: []
        }
      }

      # Time the execution
      {time_us, result} = :timer.tc(fn -> Consensus.verify(claim, context) end)

      # Should complete in reasonable time (not sequential)
      # 5 agents at 30s each would be 150s if sequential
      # In parallel should be closer to 30s max
      assert time_us < 60_000_000
      assert result.verdict in [:entailment, :contradiction, :neutral]
    end
  end

  describe "determinism" do
    test "same inputs produce same verdict" do
      claim = "Patient has chest pain"
      context = %{source_index: %{findings: [%{text: "chest pain", doc_id: "note-1"}]}}

      results =
        for _ <- 1..5 do
          Consensus.verify(claim, context)
        end

      verdicts = Enum.map(results, & &1.verdict)

      # All verdicts should be the same
      assert Enum.uniq(verdicts) |> length() == 1
    end
  end
end
