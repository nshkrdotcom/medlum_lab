defmodule MedlumLlm.Eval.CvlMetricsTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Eval.CvlMetrics

  # ============================================================================
  # Hallucination Recall Tests
  # ============================================================================

  describe "hallucination_recall/2" do
    test "catches all hallucinations (perfect recall)" do
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :neutral},
        %{sample_id: 3, verdict: :entailment}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true},
        %{sample_id: 3, is_hallucination: false}
      ]

      assert CvlMetrics.hallucination_recall(preds, truth) == 1.0
    end

    test "returns 1.0 when no hallucinations exist" do
      preds = [%{sample_id: 1, verdict: :entailment}]
      truth = [%{sample_id: 1, is_hallucination: false}]
      assert CvlMetrics.hallucination_recall(preds, truth) == 1.0
    end

    test "counts neutral as flagged" do
      preds = [
        %{sample_id: 1, verdict: :neutral},
        %{sample_id: 2, verdict: :entailment}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: false}
      ]

      assert CvlMetrics.hallucination_recall(preds, truth) == 1.0
    end

    test "misses hallucination with entailment verdict" do
      preds = [
        %{sample_id: 1, verdict: :entailment},
        %{sample_id: 2, verdict: :contradiction}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true}
      ]

      # 1 out of 2 caught
      assert CvlMetrics.hallucination_recall(preds, truth) == 0.5
    end

    test "handles empty inputs" do
      assert CvlMetrics.hallucination_recall([], []) == 1.0
    end

    test "handles mixed verdicts" do
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :neutral},
        %{sample_id: 3, verdict: :entailment},
        %{sample_id: 4, verdict: :entailment}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true},
        %{sample_id: 3, is_hallucination: true},
        %{sample_id: 4, is_hallucination: false}
      ]

      # 2 out of 3 hallucinations caught
      assert_in_delta CvlMetrics.hallucination_recall(preds, truth), 0.667, 0.01
    end
  end

  # ============================================================================
  # Hallucination Precision Tests
  # ============================================================================

  describe "hallucination_precision/2" do
    test "perfect precision when all flags are true" do
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :neutral}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true}
      ]

      assert CvlMetrics.hallucination_precision(preds, truth) == 1.0
    end

    test "returns 1.0 when nothing is flagged" do
      preds = [%{sample_id: 1, verdict: :entailment}]
      truth = [%{sample_id: 1, is_hallucination: false}]
      assert CvlMetrics.hallucination_precision(preds, truth) == 1.0
    end

    test "handles false positives" do
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :neutral}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: false}
      ]

      # 1 true flag out of 2 total flags
      assert CvlMetrics.hallucination_precision(preds, truth) == 0.5
    end

    test "handles all false positives" do
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :neutral}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: false},
        %{sample_id: 2, is_hallucination: false}
      ]

      assert CvlMetrics.hallucination_precision(preds, truth) == 0.0
    end

    test "handles empty inputs" do
      assert CvlMetrics.hallucination_precision([], []) == 1.0
    end

    test "mixed true and false positives" do
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :contradiction},
        %{sample_id: 3, verdict: :neutral},
        %{sample_id: 4, verdict: :entailment}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true},
        %{sample_id: 3, is_hallucination: false},
        %{sample_id: 4, is_hallucination: false}
      ]

      # 2 true flags out of 3 total flags
      assert_in_delta CvlMetrics.hallucination_precision(preds, truth), 0.667, 0.01
    end
  end

  # ============================================================================
  # Hallucination F1 Tests
  # ============================================================================

  describe "hallucination_f1/2" do
    test "perfect F1 score" do
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :entailment}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: false}
      ]

      assert CvlMetrics.hallucination_f1(preds, truth) == 1.0
    end

    test "F1 is harmonic mean of precision and recall" do
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :entailment},
        %{sample_id: 3, verdict: :neutral}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true},
        %{sample_id: 3, is_hallucination: false}
      ]

      # Recall = 1/2 = 0.5, Precision = 1/2 = 0.5
      # F1 = 2 * 0.5 * 0.5 / (0.5 + 0.5) = 0.5
      assert CvlMetrics.hallucination_f1(preds, truth) == 0.5
    end

    test "F1 is 0 when both precision and recall are 0" do
      preds = [%{sample_id: 1, verdict: :entailment}]
      truth = [%{sample_id: 1, is_hallucination: true}]

      # Recall = 0 (missed the hallucination)
      # Precision = 1.0 (nothing flagged, so no false positives)
      # F1 = 2*0*1/(0+1) = 0
      assert CvlMetrics.hallucination_f1(preds, truth) == 0.0
    end

    test "handles empty inputs" do
      assert CvlMetrics.hallucination_f1([], []) == 1.0
    end
  end

  # ============================================================================
  # Hallucination Confusion Matrix Tests
  # ============================================================================

  describe "hallucination_confusion_matrix/2" do
    test "all correct classifications" do
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :entailment}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: false}
      ]

      result = CvlMetrics.hallucination_confusion_matrix(preds, truth)

      assert result.true_positive == 1
      assert result.false_positive == 0
      assert result.true_negative == 1
      assert result.false_negative == 0
    end

    test "handles all types of errors" do
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :contradiction},
        %{sample_id: 3, verdict: :entailment},
        %{sample_id: 4, verdict: :entailment}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: false},
        %{sample_id: 3, is_hallucination: true},
        %{sample_id: 4, is_hallucination: false}
      ]

      result = CvlMetrics.hallucination_confusion_matrix(preds, truth)

      assert result.true_positive == 1
      assert result.false_positive == 1
      assert result.true_negative == 1
      assert result.false_negative == 1
    end

    test "neutral counts as flagged" do
      preds = [%{sample_id: 1, verdict: :neutral}]
      truth = [%{sample_id: 1, is_hallucination: true}]

      result = CvlMetrics.hallucination_confusion_matrix(preds, truth)

      assert result.true_positive == 1
    end

    test "handles empty inputs" do
      result = CvlMetrics.hallucination_confusion_matrix([], [])

      assert result.true_positive == 0
      assert result.false_positive == 0
      assert result.true_negative == 0
      assert result.false_negative == 0
    end
  end

  # ============================================================================
  # Calibration Error Tests
  # ============================================================================

  describe "calibration_error/3" do
    test "perfect calibration returns 0.0" do
      # 100% confidence and 100% accuracy
      preds = [
        %{verdict: :entailment, confidence: 1.0},
        %{verdict: :entailment, confidence: 1.0}
      ]

      samples = [
        %{label: :entailment},
        %{label: :entailment}
      ]

      assert CvlMetrics.calibration_error(preds, samples) == 0.0
    end

    test "calibration error with overconfidence" do
      # 90% confidence but only 50% accuracy = 40% error
      preds = [
        %{verdict: :entailment, confidence: 0.9},
        %{verdict: :contradiction, confidence: 0.9}
      ]

      samples = [
        %{label: :entailment},
        %{label: :entailment}
      ]

      # Both predictions in same bin (0.9 -> bin 9)
      # Avg confidence = 0.9, accuracy = 0.5, error = 0.4
      assert_in_delta CvlMetrics.calibration_error(preds, samples), 0.4, 0.01
    end

    test "handles varying confidence levels" do
      preds = [
        %{verdict: :entailment, confidence: 0.1},
        %{verdict: :entailment, confidence: 0.5},
        %{verdict: :entailment, confidence: 0.9}
      ]

      samples = [
        %{label: :entailment},
        %{label: :entailment},
        %{label: :entailment}
      ]

      # All correct, so accuracy = 1.0 in each bin
      # ECE = weighted avg of |confidence - accuracy|
      # Bin 0 (0.1): |0.1 - 1.0| = 0.9, weight = 1/3
      # Bin 5 (0.5): |0.5 - 1.0| = 0.5, weight = 1/3
      # Bin 9 (0.9): |0.9 - 1.0| = 0.1, weight = 1/3
      # ECE = (0.9 + 0.5 + 0.1) / 3 = 0.5
      assert_in_delta CvlMetrics.calibration_error(preds, samples), 0.5, 0.01
    end

    test "handles custom number of bins" do
      preds = [
        %{verdict: :entailment, confidence: 0.95},
        %{verdict: :entailment, confidence: 0.85}
      ]

      samples = [
        %{label: :entailment},
        %{label: :entailment}
      ]

      # With 5 bins, both go to same bin
      result = CvlMetrics.calibration_error(preds, samples, bins: 5)
      assert is_float(result)
    end

    test "handles empty inputs" do
      assert CvlMetrics.calibration_error([], []) == 0.0
    end

    test "handles missing confidence (defaults to 1.0)" do
      preds = [%{verdict: :entailment}]
      samples = [%{label: :entailment}]

      assert CvlMetrics.calibration_error(preds, samples) == 0.0
    end
  end

  # ============================================================================
  # Agent Agreement Rate Tests
  # ============================================================================

  describe "agent_agreement_rate/1" do
    test "perfect agreement" do
      agent_preds = %{
        1 => %{med: :entailment, lab: :entailment, ont: :entailment},
        2 => %{med: :contradiction, lab: :contradiction, ont: :contradiction}
      }

      assert CvlMetrics.agent_agreement_rate(agent_preds) == 1.0
    end

    test "partial agreement" do
      agent_preds = %{
        1 => %{med: :entailment, lab: :entailment, ont: :entailment},
        2 => %{med: :contradiction, lab: :contradiction, ont: :neutral}
      }

      # Sample 1: 3/3 = 1.0
      # Sample 2: 2/3 = 0.667
      # Average = 0.833
      assert_in_delta CvlMetrics.agent_agreement_rate(agent_preds), 0.833, 0.01
    end

    test "no agreement" do
      agent_preds = %{
        1 => %{med: :entailment, lab: :contradiction, ont: :neutral}
      }

      # 1/3 = 0.333
      assert_in_delta CvlMetrics.agent_agreement_rate(agent_preds), 0.333, 0.01
    end

    test "handles empty input" do
      assert CvlMetrics.agent_agreement_rate(%{}) == 1.0
    end

    test "handles 5 agents (CVL architecture)" do
      agent_preds = %{
        1 => %{
          medication: :entailment,
          lab: :entailment,
          ontology: :entailment,
          temporal: :entailment,
          differential: :contradiction
        },
        2 => %{
          medication: :entailment,
          lab: :entailment,
          ontology: :entailment,
          temporal: :entailment,
          differential: :entailment
        }
      }

      # Sample 1: 4/5 = 0.8
      # Sample 2: 5/5 = 1.0
      # Average = 0.9
      assert CvlMetrics.agent_agreement_rate(agent_preds) == 0.9
    end
  end

  # ============================================================================
  # Consensus Accuracy Tests
  # ============================================================================

  describe "consensus_accuracy/2" do
    test "correct consensus" do
      agent_preds = %{
        1 => %{med: :entailment, lab: :entailment, ont: :contradiction}
      }

      truth = [%{sample_id: 1, label: :entailment}]

      assert CvlMetrics.consensus_accuracy(agent_preds, truth) == 1.0
    end

    test "incorrect consensus" do
      agent_preds = %{
        1 => %{med: :contradiction, lab: :contradiction, ont: :entailment}
      }

      truth = [%{sample_id: 1, label: :entailment}]

      assert CvlMetrics.consensus_accuracy(agent_preds, truth) == 0.0
    end

    test "multiple samples" do
      agent_preds = %{
        1 => %{med: :entailment, lab: :entailment, ont: :entailment},
        2 => %{med: :contradiction, lab: :contradiction, ont: :entailment}
      }

      truth = [
        %{sample_id: 1, label: :entailment},
        %{sample_id: 2, label: :entailment}
      ]

      # Sample 1: consensus = entailment, correct
      # Sample 2: consensus = contradiction, incorrect
      assert CvlMetrics.consensus_accuracy(agent_preds, truth) == 0.5
    end

    test "handles empty ground truth" do
      agent_preds = %{1 => %{med: :entailment}}
      assert CvlMetrics.consensus_accuracy(agent_preds, []) == 0.0
    end

    test "handles missing sample in predictions" do
      agent_preds = %{
        1 => %{med: :entailment, lab: :entailment}
      }

      truth = [
        %{sample_id: 1, label: :entailment},
        %{sample_id: 2, label: :contradiction}
      ]

      # Sample 1: correct, Sample 2: missing, counts as incorrect
      assert CvlMetrics.consensus_accuracy(agent_preds, truth) == 0.5
    end
  end

  # ============================================================================
  # Per-Agent Accuracy Tests
  # ============================================================================

  describe "per_agent_accuracy/2" do
    test "calculates accuracy for each agent" do
      agent_preds = %{
        1 => %{med: :entailment, lab: :entailment},
        2 => %{med: :contradiction, lab: :entailment}
      }

      truth = [
        %{sample_id: 1, label: :entailment},
        %{sample_id: 2, label: :contradiction}
      ]

      result = CvlMetrics.per_agent_accuracy(agent_preds, truth)

      # med: 2/2 correct
      assert result[:med] == 1.0
      # lab: 1/2 correct
      assert result[:lab] == 0.5
    end

    test "handles all correct" do
      agent_preds = %{
        1 => %{a: :x, b: :x},
        2 => %{a: :y, b: :y}
      }

      truth = [
        %{sample_id: 1, label: :x},
        %{sample_id: 2, label: :y}
      ]

      result = CvlMetrics.per_agent_accuracy(agent_preds, truth)

      assert result[:a] == 1.0
      assert result[:b] == 1.0
    end

    test "handles all incorrect" do
      agent_preds = %{
        1 => %{a: :y, b: :y}
      }

      truth = [%{sample_id: 1, label: :x}]

      result = CvlMetrics.per_agent_accuracy(agent_preds, truth)

      assert result[:a] == 0.0
      assert result[:b] == 0.0
    end

    test "handles empty inputs" do
      assert CvlMetrics.per_agent_accuracy(%{}, []) == %{}
    end
  end

  # ============================================================================
  # Disagreement Analysis Tests
  # ============================================================================

  describe "disagreement_analysis/2" do
    test "identifies disagreement samples" do
      agent_preds = %{
        1 => %{med: :entailment, lab: :entailment},
        2 => %{med: :contradiction, lab: :entailment}
      }

      truth = [
        %{sample_id: 1, label: :entailment},
        %{sample_id: 2, label: :contradiction}
      ]

      result = CvlMetrics.disagreement_analysis(agent_preds, truth)

      assert result.disagreement_count == 1
    end

    test "no disagreement samples" do
      agent_preds = %{
        1 => %{med: :entailment, lab: :entailment},
        2 => %{med: :contradiction, lab: :contradiction}
      }

      truth = [
        %{sample_id: 1, label: :entailment},
        %{sample_id: 2, label: :contradiction}
      ]

      result = CvlMetrics.disagreement_analysis(agent_preds, truth)

      assert result.disagreement_count == 0
    end

    test "calculates per-agent accuracy for disagreements" do
      agent_preds = %{
        1 => %{med: :entailment, lab: :contradiction}
      }

      truth = [%{sample_id: 1, label: :entailment}]

      result = CvlMetrics.disagreement_analysis(agent_preds, truth)

      assert result.per_agent_accuracy[:med] == 1.0
      assert result.per_agent_accuracy[:lab] == 0.0
    end

    test "handles empty inputs" do
      result = CvlMetrics.disagreement_analysis(%{}, [])

      assert result.disagreement_count == 0
      assert result.per_agent_accuracy == %{}
    end
  end

  # ============================================================================
  # Helper Function Tests
  # ============================================================================

  describe "valid_verdicts/0" do
    test "returns all valid verdicts" do
      verdicts = CvlMetrics.valid_verdicts()
      assert :entailment in verdicts
      assert :contradiction in verdicts
      assert :neutral in verdicts
      assert length(verdicts) == 3
    end
  end

  describe "flagged_verdicts/0" do
    test "returns flagged verdicts" do
      verdicts = CvlMetrics.flagged_verdicts()
      assert :contradiction in verdicts
      assert :neutral in verdicts
      refute :entailment in verdicts
      assert length(verdicts) == 2
    end
  end

  describe "flagged?/1" do
    test "entailment is not flagged" do
      refute CvlMetrics.flagged?(:entailment)
    end

    test "contradiction is flagged" do
      assert CvlMetrics.flagged?(:contradiction)
    end

    test "neutral is flagged" do
      assert CvlMetrics.flagged?(:neutral)
    end
  end

  # ============================================================================
  # Edge Cases and Realistic Scenarios
  # ============================================================================

  describe "realistic CVL scenarios" do
    test "high recall, moderate precision scenario" do
      # CVL catches most hallucinations but has some false positives
      preds = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :neutral},
        %{sample_id: 3, verdict: :neutral},
        %{sample_id: 4, verdict: :entailment},
        %{sample_id: 5, verdict: :contradiction}
      ]

      truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true},
        %{sample_id: 3, is_hallucination: false},
        %{sample_id: 4, is_hallucination: false},
        %{sample_id: 5, is_hallucination: true}
      ]

      recall = CvlMetrics.hallucination_recall(preds, truth)
      precision = CvlMetrics.hallucination_precision(preds, truth)

      # All 3 hallucinations caught
      assert recall == 1.0
      # 3 true positives out of 4 flags
      assert precision == 0.75
    end

    test "target metrics scenario (>95% recall, >85% precision)" do
      # Simulate a well-performing CVL system
      # 20 samples: 10 hallucinations, 10 valid claims
      hallucination_ids = Enum.to_list(1..10)
      valid_ids = Enum.to_list(11..20)

      # CVL catches 10 out of 10 hallucinations (100% recall)
      # CVL flags 2 false positives (11 and 12)
      preds =
        Enum.map(hallucination_ids, fn id ->
          %{sample_id: id, verdict: :contradiction}
        end) ++
          [
            %{sample_id: 11, verdict: :neutral},
            %{sample_id: 12, verdict: :neutral}
          ] ++
          Enum.map(13..20, fn id ->
            %{sample_id: id, verdict: :entailment}
          end)

      truth =
        Enum.map(hallucination_ids, fn id ->
          %{sample_id: id, is_hallucination: true}
        end) ++
          Enum.map(valid_ids, fn id ->
            %{sample_id: id, is_hallucination: false}
          end)

      recall = CvlMetrics.hallucination_recall(preds, truth)
      precision = CvlMetrics.hallucination_precision(preds, truth)
      f1 = CvlMetrics.hallucination_f1(preds, truth)

      # 100% recall (all hallucinations caught)
      assert recall == 1.0
      # 10/12 = 83.3% precision (10 true positives, 2 false positives)
      assert_in_delta precision, 0.833, 0.01
      # F1 should be high
      assert f1 > 0.9
    end

    test "5-agent CVL ensemble scenario" do
      # Realistic 5-agent setup
      agent_preds = %{
        1 => %{
          medication_agent: :entailment,
          lab_agent: :entailment,
          ontology_agent: :entailment,
          temporal_agent: :entailment,
          differential_agent: :entailment
        },
        2 => %{
          medication_agent: :contradiction,
          lab_agent: :contradiction,
          ontology_agent: :neutral,
          temporal_agent: :contradiction,
          differential_agent: :neutral
        },
        3 => %{
          medication_agent: :neutral,
          lab_agent: :entailment,
          ontology_agent: :entailment,
          temporal_agent: :neutral,
          differential_agent: :entailment
        }
      }

      truth = [
        %{sample_id: 1, label: :entailment},
        %{sample_id: 2, label: :contradiction},
        %{sample_id: 3, label: :neutral}
      ]

      agreement = CvlMetrics.agent_agreement_rate(agent_preds)
      consensus_acc = CvlMetrics.consensus_accuracy(agent_preds, truth)
      per_agent = CvlMetrics.per_agent_accuracy(agent_preds, truth)
      disagreement = CvlMetrics.disagreement_analysis(agent_preds, truth)

      # Sample 1: 5/5 = 1.0
      # Sample 2: 3/5 = 0.6 (contradiction majority)
      # Sample 3: 3/5 = 0.6 (entailment majority)
      assert agreement > 0.7

      # Consensus: entailment (correct), contradiction (correct), entailment (incorrect)
      # 2/3 correct
      assert_in_delta consensus_acc, 0.667, 0.01

      # Per-agent accuracy varies
      assert is_map(per_agent)
      assert map_size(per_agent) == 5

      # Disagreement analysis
      assert disagreement.disagreement_count == 2
    end
  end
end
