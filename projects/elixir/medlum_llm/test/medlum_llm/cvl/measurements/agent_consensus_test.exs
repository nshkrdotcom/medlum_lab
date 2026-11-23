defmodule MedlumLlm.CVL.Measurements.AgentConsensusTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.Measurements.AgentConsensus

  describe "compute/1" do
    test "returns neutral with insufficient agents" do
      sample = make_sample(%{
        medication: %{verdict: :entailment, confidence: 0.9}
      })

      {:ok, results} = AgentConsensus.compute([sample])

      result = results[sample.id]
      assert result.verdict == :neutral
      assert result.reasoning =~ "Insufficient agent verdicts"
    end

    test "computes consensus from multiple agents" do
      sample = make_sample(%{
        medication: %{verdict: :entailment, confidence: 0.9},
        lab: %{verdict: :entailment, confidence: 0.85},
        ontology: %{verdict: :entailment, confidence: 0.8}
      })

      {:ok, results} = AgentConsensus.compute([sample])

      result = results[sample.id]
      assert result.verdict == :entailment
      assert result.agreement > 0.9
    end

    test "handles mixed verdicts" do
      sample = make_sample(%{
        medication: %{verdict: :entailment, confidence: 0.9},
        lab: %{verdict: :contradiction, confidence: 0.85},
        ontology: %{verdict: :neutral, confidence: 0.8}
      })

      {:ok, results} = AgentConsensus.compute([sample])

      result = results[sample.id]
      # Should have some consensus but with mixed verdicts
      assert result.verdict in [:entailment, :contradiction, :neutral]
      assert result.agreement < 1.0
    end

    test "vetos with multiple contradictions" do
      sample = make_sample(%{
        medication: %{verdict: :contradiction, confidence: 0.9},
        lab: %{verdict: :contradiction, confidence: 0.85},
        ontology: %{verdict: :entailment, confidence: 0.8}
      })

      {:ok, results} = AgentConsensus.compute([sample])

      result = results[sample.id]
      assert result.verdict == :contradiction
      assert result.reasoning =~ "veto"
    end

    test "includes weighted votes" do
      sample = make_sample(%{
        medication: %{verdict: :entailment, confidence: 0.9},
        lab: %{verdict: :entailment, confidence: 0.85},
        ontology: %{verdict: :neutral, confidence: 0.8}
      })

      {:ok, results} = AgentConsensus.compute([sample])

      result = results[sample.id]
      assert Map.has_key?(result.weighted_votes, :entailment)
      assert result.weighted_votes.entailment > 0
    end

    test "processes multiple samples" do
      samples = [
        make_sample(%{
          medication: %{verdict: :entailment, confidence: 0.9},
          lab: %{verdict: :entailment, confidence: 0.85}
        }),
        make_sample(%{
          medication: %{verdict: :contradiction, confidence: 0.9},
          lab: %{verdict: :contradiction, confidence: 0.85}
        })
      ]

      {:ok, results} = AgentConsensus.compute(samples)

      assert map_size(results) == 2
    end
  end

  describe "dependencies/0" do
    test "includes all agent measurements" do
      deps = AgentConsensus.dependencies()

      assert length(deps) == 5
      assert MedlumLlm.CVL.Measurements.MedicationAgent in deps
      assert MedlumLlm.CVL.Measurements.LabAgent in deps
      assert MedlumLlm.CVL.Measurements.OntologyAgent in deps
      assert MedlumLlm.CVL.Measurements.TemporalAgent in deps
      assert MedlumLlm.CVL.Measurements.DifferentialAgent in deps
    end
  end

  describe "key/0" do
    test "returns stable key" do
      assert String.starts_with?(AgentConsensus.key(), "agent_consensus_")
    end
  end

  describe "config/0" do
    test "includes agent weights" do
      config = AgentConsensus.config()

      assert Map.has_key?(config, :agent_weights)
      assert config.agent_weights.medication > 0
    end
  end

  defp make_sample(measurements) do
    %Forge.Sample{
      id: "test_#{System.unique_integer()}",
      pipeline: :test,
      data: %{},
      measurements: measurements,
      status: :pending,
      created_at: DateTime.utc_now()
    }
  end
end
