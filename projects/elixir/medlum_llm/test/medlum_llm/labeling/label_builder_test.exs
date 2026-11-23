defmodule MedlumLlm.Labeling.LabelBuilderTest do
  use ExUnit.Case, async: true

  alias LabelingIR.Label
  alias MedlumLlm.Labeling.LabelBuilder

  describe "build_nli_label/1" do
    test "creates valid Label struct with required fields" do
      label =
        LabelBuilder.build_nli_label(%{
          assignment_id: "assign_001",
          sample_id: "sample_001",
          queue_id: "cvl_queue",
          tenant_id: "medlum",
          user_id: "alice",
          verdict: :contradiction,
          time_spent_ms: 30_000
        })

      assert %Label{} = label
      assert String.starts_with?(label.id, "lbl_")
      assert label.assignment_id == "assign_001"
      assert label.sample_id == "sample_001"
      assert label.queue_id == "cvl_queue"
      assert label.tenant_id == "medlum"
      assert label.user_id == "alice"
      assert label.time_spent_ms == 30_000
    end

    test "sets nli_label value from verdict" do
      label =
        LabelBuilder.build_nli_label(%{
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          user_id: "u",
          verdict: :entailment,
          time_spent_ms: 1000
        })

      assert label.values["nli_label"] == "ENTAILMENT"
    end

    test "includes optional fields when provided" do
      label =
        LabelBuilder.build_nli_label(%{
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          user_id: "u",
          verdict: :contradiction,
          time_spent_ms: 1000,
          confidence: 4,
          reasoning: "Medication dose differs",
          evidence_spans: "metformin 500mg BID",
          difficulty: "easy"
        })

      assert label.values["confidence"] == 4
      assert label.values["reasoning"] == "Medication dose differs"
      assert label.values["evidence_spans"] == "metformin 500mg BID"
      assert label.values["difficulty"] == "easy"
    end

    test "excludes nil optional fields from values" do
      label =
        LabelBuilder.build_nli_label(%{
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          user_id: "u",
          verdict: :neutral,
          time_spent_ms: 1000,
          confidence: 3
          # reasoning, evidence_spans, difficulty not provided
        })

      refute Map.has_key?(label.values, "reasoning")
      refute Map.has_key?(label.values, "evidence_spans")
      refute Map.has_key?(label.values, "difficulty")
    end

    test "sets namespace when provided" do
      label =
        LabelBuilder.build_nli_label(%{
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          user_id: "u",
          verdict: :entailment,
          time_spent_ms: 1000,
          namespace: "training"
        })

      assert label.namespace == "training"
    end

    test "sets notes when provided" do
      label =
        LabelBuilder.build_nli_label(%{
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          user_id: "u",
          verdict: :entailment,
          time_spent_ms: 1000,
          notes: "Edge case example"
        })

      assert label.notes == "Edge case example"
    end

    test "sets created_at timestamp" do
      before = DateTime.utc_now()

      label =
        LabelBuilder.build_nli_label(%{
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          user_id: "u",
          verdict: :entailment,
          time_spent_ms: 1000
        })

      after_time = DateTime.utc_now()

      assert DateTime.compare(label.created_at, before) in [:gt, :eq]
      assert DateTime.compare(label.created_at, after_time) in [:lt, :eq]
    end

    test "can be serialized to JSON" do
      label =
        LabelBuilder.build_nli_label(%{
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          user_id: "u",
          verdict: :contradiction,
          time_spent_ms: 1000
        })

      assert {:ok, _json} = Jason.encode(label)
    end
  end

  describe "build_agent_label/3" do
    test "creates valid Label struct" do
      verdict = %{
        verdict: :contradiction,
        confidence: 0.92,
        evidence: ["Dose mismatch"],
        ontology_codes: ["861004"]
      }

      label =
        LabelBuilder.build_agent_label(
          :medication,
          verdict,
          assignment_id: "assign_001",
          sample_id: "sample_001",
          queue_id: "agent_queue",
          tenant_id: "medlum",
          agent_id: "medication_agent_v1",
          time_spent_ms: 150
        )

      assert %Label{} = label
      assert String.starts_with?(label.id, "lbl_")
    end

    test "sets user_id with agent: prefix" do
      verdict = %{
        verdict: :entailment,
        confidence: 0.85,
        evidence: [],
        ontology_codes: []
      }

      label =
        LabelBuilder.build_agent_label(
          :lab,
          verdict,
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          agent_id: "lab_agent_v2",
          time_spent_ms: 100
        )

      assert label.user_id == "agent:lab_agent_v2"
    end

    test "sets correct values structure" do
      verdict = %{
        verdict: :contradiction,
        confidence: 0.92,
        evidence: ["Dose mismatch: 500mg vs 1000mg"],
        ontology_codes: ["861004", "123456"]
      }

      label =
        LabelBuilder.build_agent_label(
          :medication,
          verdict,
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          agent_id: "med_agent",
          time_spent_ms: 150
        )

      assert label.values["agent_type"] == "medication"
      assert label.values["verdict"] == "CONTRADICTION"
      assert label.values["confidence"] == 0.92
      assert label.values["evidence"] == ["Dose mismatch: 500mg vs 1000mg"]
      assert label.values["ontology_codes"] == ["861004", "123456"]
    end

    test "sets is_agent_label in metadata" do
      verdict = %{
        verdict: :neutral,
        confidence: 0.5,
        evidence: [],
        ontology_codes: []
      }

      label =
        LabelBuilder.build_agent_label(
          :ontology,
          verdict,
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          agent_id: "ontology_agent",
          time_spent_ms: 200
        )

      assert label.metadata["is_agent_label"] == true
      assert label.metadata["agent_version"] == "ontology_agent"
    end

    test "can be serialized to JSON" do
      verdict = %{
        verdict: :entailment,
        confidence: 0.9,
        evidence: [],
        ontology_codes: []
      }

      label =
        LabelBuilder.build_agent_label(
          :temporal,
          verdict,
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          agent_id: "temporal_agent",
          time_spent_ms: 100
        )

      assert {:ok, _json} = Jason.encode(label)
    end
  end

  describe "build_consensus_label/2" do
    test "creates valid Label struct" do
      consensus = %{
        agent_verdicts: %{
          medication: %{
            verdict: :contradiction,
            confidence: 0.9,
            evidence: ["Dose mismatch"],
            ontology_codes: ["861004"]
          },
          lab: %{
            verdict: :entailment,
            confidence: 0.8,
            evidence: [],
            ontology_codes: []
          }
        },
        consensus_verdict: :contradiction,
        consensus_method: :weighted_vote,
        dissent_count: 1
      }

      label =
        LabelBuilder.build_consensus_label(
          consensus,
          assignment_id: "assign_001",
          sample_id: "sample_001",
          queue_id: "consensus_queue",
          tenant_id: "medlum",
          time_spent_ms: 500
        )

      assert %Label{} = label
      assert label.user_id == "agent:cvl_consensus"
    end

    test "sets correct consensus values" do
      consensus = %{
        agent_verdicts: %{
          medication: %{
            verdict: :contradiction,
            confidence: 0.9,
            evidence: [],
            ontology_codes: []
          }
        },
        consensus_verdict: :contradiction,
        consensus_method: :majority_vote,
        dissent_count: 0
      }

      label =
        LabelBuilder.build_consensus_label(
          consensus,
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          time_spent_ms: 300
        )

      assert label.values["consensus_verdict"] == "CONTRADICTION"
      assert label.values["consensus_method"] == "majority_vote"
      assert label.values["dissent_count"] == 0
    end

    test "serializes agent verdicts" do
      consensus = %{
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
            evidence: ["Values match"],
            ontology_codes: ["4548-4"]
          }
        },
        consensus_verdict: :contradiction,
        consensus_method: :weighted_vote,
        dissent_count: 1
      }

      label =
        LabelBuilder.build_consensus_label(
          consensus,
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          time_spent_ms: 500
        )

      agent_verdicts = label.values["agent_verdicts"]

      assert agent_verdicts["medication"]["verdict"] == "CONTRADICTION"
      assert agent_verdicts["medication"]["confidence"] == 0.92
      assert agent_verdicts["lab"]["verdict"] == "ENTAILMENT"
    end

    test "sets is_consensus_label in metadata" do
      consensus = %{
        agent_verdicts: %{},
        consensus_verdict: :neutral,
        consensus_method: :unanimous,
        dissent_count: 0
      }

      label =
        LabelBuilder.build_consensus_label(
          consensus,
          assignment_id: "a",
          sample_id: "s",
          queue_id: "q",
          tenant_id: "t",
          time_spent_ms: 100
        )

      assert label.metadata["is_consensus_label"] == true
    end
  end

  describe "generate_label_id/0" do
    test "generates IDs with lbl_ prefix" do
      id = LabelBuilder.generate_label_id()
      assert String.starts_with?(id, "lbl_")
    end

    test "generates unique IDs" do
      ids = for _ <- 1..100, do: LabelBuilder.generate_label_id()
      assert length(Enum.uniq(ids)) == 100
    end

    test "generates IDs of consistent length" do
      id = LabelBuilder.generate_label_id()
      # "lbl_" (4) + 24 hex chars = 28
      assert String.length(id) == 28
    end
  end
end
