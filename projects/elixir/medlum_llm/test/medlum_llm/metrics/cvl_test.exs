defmodule MedlumLlm.Metrics.CVLTest do
  use ExUnit.Case, async: false

  alias MedlumLlm.Metrics.CVL
  alias MetricsEx.Storage.ETS

  setup do
    ETS.clear()
    :ok
  end

  describe "agents/0" do
    test "returns the list of CVL agents" do
      agents = CVL.agents()

      assert :medication in agents
      assert :lab in agents
      assert :ontology in agents
      assert :temporal in agents
      assert :differential in agents
      assert length(agents) == 5
    end
  end

  describe "verdicts/0" do
    test "returns the list of possible verdicts" do
      verdicts = CVL.verdicts()

      assert :entailment in verdicts
      assert :contradiction in verdicts
      assert :neutral in verdicts
      assert length(verdicts) == 3
    end
  end

  describe "record_verification/3" do
    test "records verdict count" do
      CVL.record_verification(:contradiction, 100.0, verifier_type: :ensemble)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_verdict_count)
      assert length(results) == 1
      metric = hd(results)
      assert metric.tags.verdict == :contradiction
      assert metric.tags.verifier_type == :ensemble
    end

    test "records verification duration" do
      CVL.record_verification(:entailment, 150.5, verifier_type: :single_agent)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_verify_duration_ms)
      assert length(results) == 1
      metric = hd(results)
      assert metric.value == 150.5
      assert metric.type == :histogram
    end

    test "records confidence when provided" do
      CVL.record_verification(:neutral, 100.0,
        verifier_type: :ensemble,
        confidence: 0.85
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_confidence)
      assert length(results) == 1
      metric = hd(results)
      assert metric.value == 0.85
    end

    test "includes run_id in tags when provided" do
      CVL.record_verification(:entailment, 100.0,
        verifier_type: :ensemble,
        run_id: "run_123"
      )

      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_verdict_count)
      metric = hd(results)
      assert metric.tags.run_id == "run_123"
    end
  end

  describe "record_agent_verdict/4" do
    test "records agent verdict for all agents" do
      for agent <- CVL.agents() do
        CVL.record_agent_verdict(agent, :entailment, 50.0)
      end

      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_agent_verdict_count)
      assert length(results) == 5
    end

    test "records agent duration" do
      CVL.record_agent_verdict(:medication, :contradiction, 45.2)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_agent_duration_ms)
      assert length(results) == 1
      metric = hd(results)
      assert metric.value == 45.2
      assert metric.tags.agent == :medication
      assert metric.tags.verdict == :contradiction
    end

    test "records agent confidence when provided" do
      CVL.record_agent_verdict(:lab, :neutral, 30.0, confidence: 0.72)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_agent_confidence)
      assert length(results) == 1
      metric = hd(results)
      assert metric.value == 0.72
      assert metric.tags.agent == :lab
    end
  end

  describe "record_consensus/4" do
    test "records consensus duration" do
      CVL.record_consensus(:entailment, 4, 180.0, run_id: "run_123")
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_consensus_duration_ms)
      assert length(results) == 1
      metric = hd(results)
      assert metric.value == 180.0
      assert metric.tags.verdict == :entailment
    end

    test "records agreement count" do
      CVL.record_consensus(:contradiction, 3, 200.0)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_agreement_count)
      assert length(results) == 1
      metric = hd(results)
      assert metric.value == 3
    end

    test "records agreement rate as fraction" do
      CVL.record_consensus(:neutral, 5, 150.0)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_agreement_rate)
      assert length(results) == 1
      metric = hd(results)
      assert metric.value == 1.0
    end

    test "calculates correct agreement rate for partial consensus" do
      CVL.record_consensus(:entailment, 3, 100.0)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_agreement_rate)
      metric = hd(results)
      # 3 out of 5 agents = 0.6
      assert metric.value == 0.6
    end
  end

  describe "record_hallucination_detection/3" do
    test "records true positive" do
      CVL.record_hallucination_detection(true, true, verifier_type: :ensemble)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_detection_outcome)
      assert length(results) == 1
      metric = hd(results)
      assert metric.tags.outcome == :true_positive
      assert metric.tags.verifier_type == :ensemble
    end

    test "records false positive" do
      CVL.record_hallucination_detection(true, false)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_detection_outcome)
      metric = hd(results)
      assert metric.tags.outcome == :false_positive
    end

    test "records true negative" do
      CVL.record_hallucination_detection(false, false)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_detection_outcome)
      metric = hd(results)
      assert metric.tags.outcome == :true_negative
    end

    test "records false negative" do
      CVL.record_hallucination_detection(false, true)
      Process.sleep(50)

      results = ETS.query(name: :medlum_cvl_detection_outcome)
      metric = hd(results)
      assert metric.tags.outcome == :false_negative
    end
  end
end
