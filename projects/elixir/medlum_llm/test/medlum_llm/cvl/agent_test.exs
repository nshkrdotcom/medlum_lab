defmodule MedlumLlm.CVL.AgentTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.Agent

  describe "aggregate_verdicts/1" do
    test "returns neutral for empty list" do
      result = Agent.aggregate_verdicts([])
      assert result.verdict == :neutral
      assert result.confidence == 0.0
      assert result.explanations == ["No claims to verify"]
    end

    test "returns contradiction if any contradiction" do
      verdicts = [
        {:entailment, "good"},
        {:contradiction, "bad"},
        {:entailment, "good"}
      ]

      result = Agent.aggregate_verdicts(verdicts)
      assert result.verdict == :contradiction
      # 1 contradiction out of 3 verdicts
      assert result.confidence == 1 / 3
    end

    test "returns entailment if majority entailment" do
      verdicts = [
        {:entailment, "good 1"},
        {:entailment, "good 2"},
        {:neutral, "neutral"}
      ]

      result = Agent.aggregate_verdicts(verdicts)
      assert result.verdict == :entailment
      # 2 entailments out of 3 verdicts
      assert result.confidence == 2 / 3
    end

    test "returns neutral if no clear majority" do
      verdicts = [
        {:neutral, "neutral 1"},
        {:neutral, "neutral 2"}
      ]

      result = Agent.aggregate_verdicts(verdicts)
      assert result.verdict == :neutral
      assert result.confidence == 1.0
    end

    test "returns neutral when entailment equals neutral" do
      verdicts = [
        {:entailment, "good"},
        {:neutral, "unsure"}
      ]

      result = Agent.aggregate_verdicts(verdicts)
      # When entailment == neutral, neutral wins (conservative)
      assert result.verdict == :neutral
    end

    test "preserves explanations in result" do
      verdicts = [
        {:entailment, "Medication verified"},
        {:entailment, "Dose valid"}
      ]

      result = Agent.aggregate_verdicts(verdicts)
      assert "Medication verified" in result.explanations
      assert "Dose valid" in result.explanations
    end

    test "stores sub_verdicts in result" do
      verdicts = [
        {:entailment, "good"},
        {:neutral, "uncertain"}
      ]

      result = Agent.aggregate_verdicts(verdicts)
      assert result.sub_verdicts == verdicts
    end

    test "initializes evidence as empty list" do
      verdicts = [{:entailment, "good"}]

      result = Agent.aggregate_verdicts(verdicts)
      assert result.evidence == []
    end

    test "contradiction takes precedence over all others" do
      verdicts = [
        {:entailment, "good 1"},
        {:entailment, "good 2"},
        {:entailment, "good 3"},
        {:contradiction, "bad"}
      ]

      result = Agent.aggregate_verdicts(verdicts)
      assert result.verdict == :contradiction
    end

    test "multiple contradictions increase confidence" do
      verdicts = [
        {:contradiction, "bad 1"},
        {:contradiction, "bad 2"},
        {:entailment, "good"}
      ]

      result = Agent.aggregate_verdicts(verdicts)
      assert result.verdict == :contradiction
      # 2 contradictions out of 3 verdicts
      assert result.confidence == 2 / 3
    end
  end
end
