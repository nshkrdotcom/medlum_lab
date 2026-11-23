# CVL Evaluation Example
#
# Run with: mix run examples/cvl_evaluation.exs
#
# This example demonstrates MedlumLlm's CVL (Clinical Verification Layer)
# evaluation metrics for hallucination detection in medical AI systems.

alias MedlumLlm.Eval.CvlMetrics

IO.puts("=" |> String.duplicate(60))
IO.puts("MedlumLlm CVL Evaluation Example")
IO.puts("=" |> String.duplicate(60))

# ============================================================================
# 1. Hallucination Detection Metrics
# ============================================================================

IO.puts("\n1. HALLUCINATION DETECTION METRICS")
IO.puts("-" |> String.duplicate(40))

# Simulated CVL predictions (verdict classification)
# In a real system, these come from the CVL multi-agent pipeline
cvl_predictions = [
  %{sample_id: 1, verdict: :contradiction, confidence: 0.95},
  %{sample_id: 2, verdict: :neutral, confidence: 0.78},
  %{sample_id: 3, verdict: :entailment, confidence: 0.92},
  %{sample_id: 4, verdict: :contradiction, confidence: 0.88},
  %{sample_id: 5, verdict: :entailment, confidence: 0.85},
  %{sample_id: 6, verdict: :neutral, confidence: 0.72},
  %{sample_id: 7, verdict: :entailment, confidence: 0.91},
  %{sample_id: 8, verdict: :contradiction, confidence: 0.94},
  %{sample_id: 9, verdict: :entailment, confidence: 0.89},
  %{sample_id: 10, verdict: :neutral, confidence: 0.65}
]

# Ground truth: which samples actually contain hallucinations
ground_truth = [
  %{sample_id: 1, is_hallucination: true},   # Correctly flagged (contradiction)
  %{sample_id: 2, is_hallucination: true},   # Correctly flagged (neutral)
  %{sample_id: 3, is_hallucination: false},  # Correctly not flagged
  %{sample_id: 4, is_hallucination: true},   # Correctly flagged
  %{sample_id: 5, is_hallucination: false},  # Correctly not flagged
  %{sample_id: 6, is_hallucination: false},  # False positive (neutral flagged non-hallucination)
  %{sample_id: 7, is_hallucination: false},  # Correctly not flagged
  %{sample_id: 8, is_hallucination: true},   # Correctly flagged
  %{sample_id: 9, is_hallucination: true},   # False negative (missed hallucination)
  %{sample_id: 10, is_hallucination: true}   # Correctly flagged (neutral)
]

recall = CvlMetrics.hallucination_recall(cvl_predictions, ground_truth)
precision = CvlMetrics.hallucination_precision(cvl_predictions, ground_truth)
f1 = CvlMetrics.hallucination_f1(cvl_predictions, ground_truth)

IO.puts("Hallucination Detection Results:")
IO.puts("  Recall:    #{Float.round(recall * 100, 1)}% (target: >95%)")
IO.puts("  Precision: #{Float.round(precision * 100, 1)}% (target: >85%)")
IO.puts("  F1 Score:  #{Float.round(f1, 3)}")

# Check targets
IO.puts("\nTarget Assessment:")
if recall >= 0.95, do: IO.puts("  [PASS] Recall meets 95% target"), else: IO.puts("  [FAIL] Recall below 95% target")
if precision >= 0.85, do: IO.puts("  [PASS] Precision meets 85% target"), else: IO.puts("  [FAIL] Precision below 85% target")

# ============================================================================
# 2. Confusion Matrix
# ============================================================================

IO.puts("\n2. CONFUSION MATRIX")
IO.puts("-" |> String.duplicate(40))

cm = CvlMetrics.hallucination_confusion_matrix(cvl_predictions, ground_truth)

IO.puts("                  Predicted")
IO.puts("                  Flagged   Not Flagged")
IO.puts("Actual Halluc.      #{cm.true_positive}          #{cm.false_negative}")
IO.puts("Actual Valid        #{cm.false_positive}          #{cm.true_negative}")

IO.puts("\nBreakdown:")
IO.puts("  True Positives:  #{cm.true_positive} (correctly flagged hallucinations)")
IO.puts("  False Positives: #{cm.false_positive} (incorrectly flagged valid claims)")
IO.puts("  True Negatives:  #{cm.true_negative} (correctly passed valid claims)")
IO.puts("  False Negatives: #{cm.false_negative} (missed hallucinations)")

# ============================================================================
# 3. Calibration Error
# ============================================================================

IO.puts("\n3. CALIBRATION ERROR (ECE)")
IO.puts("-" |> String.duplicate(40))

# For NLI classification accuracy calibration
nli_predictions = [
  %{verdict: :entailment, confidence: 0.9},
  %{verdict: :entailment, confidence: 0.85},
  %{verdict: :contradiction, confidence: 0.95},
  %{verdict: :neutral, confidence: 0.7},
  %{verdict: :entailment, confidence: 0.8},
  %{verdict: :contradiction, confidence: 0.9}
]

nli_ground_truth = [
  %{label: :entailment},     # Correct at 90% conf
  %{label: :entailment},     # Correct at 85% conf
  %{label: :contradiction},  # Correct at 95% conf
  %{label: :neutral},        # Correct at 70% conf
  %{label: :contradiction},  # Wrong at 80% conf
  %{label: :contradiction}   # Correct at 90% conf
]

ece = CvlMetrics.calibration_error(nli_predictions, nli_ground_truth)

IO.puts("Expected Calibration Error: #{Float.round(ece, 3)}")
IO.puts("  0.0 = Perfect calibration")
IO.puts("  1.0 = Complete miscalibration")

cond do
  ece < 0.1 -> IO.puts("  [EXCELLENT] Well-calibrated model")
  ece < 0.2 -> IO.puts("  [GOOD] Reasonably calibrated model")
  true -> IO.puts("  [NEEDS IMPROVEMENT] Consider calibration techniques")
end

# ============================================================================
# 4. Multi-Agent Metrics (5-Agent CVL Architecture)
# ============================================================================

IO.puts("\n4. MULTI-AGENT METRICS (5-Agent CVL)")
IO.puts("-" |> String.duplicate(40))

# Simulated 5-agent predictions per sample
# These represent the verdicts from each specialized CVL agent
agent_predictions = %{
  1 => %{
    medication_agent: :contradiction,
    lab_agent: :contradiction,
    ontology_agent: :contradiction,
    temporal_agent: :contradiction,
    differential_agent: :contradiction
  },
  2 => %{
    medication_agent: :neutral,
    lab_agent: :neutral,
    ontology_agent: :entailment,
    temporal_agent: :neutral,
    differential_agent: :neutral
  },
  3 => %{
    medication_agent: :entailment,
    lab_agent: :entailment,
    ontology_agent: :entailment,
    temporal_agent: :entailment,
    differential_agent: :entailment
  },
  4 => %{
    medication_agent: :contradiction,
    lab_agent: :contradiction,
    ontology_agent: :contradiction,
    temporal_agent: :neutral,
    differential_agent: :contradiction
  },
  5 => %{
    medication_agent: :entailment,
    lab_agent: :entailment,
    ontology_agent: :entailment,
    temporal_agent: :contradiction,
    differential_agent: :entailment
  }
}

nli_truth = [
  %{sample_id: 1, label: :contradiction},
  %{sample_id: 2, label: :neutral},
  %{sample_id: 3, label: :entailment},
  %{sample_id: 4, label: :contradiction},
  %{sample_id: 5, label: :entailment}
]

agreement_rate = CvlMetrics.agent_agreement_rate(agent_predictions)
consensus_acc = CvlMetrics.consensus_accuracy(agent_predictions, nli_truth)
per_agent = CvlMetrics.per_agent_accuracy(agent_predictions, nli_truth)

IO.puts("Agent Agreement Rate: #{Float.round(agreement_rate * 100, 1)}% (target: >80%)")
IO.puts("Consensus Accuracy:   #{Float.round(consensus_acc * 100, 1)}%")

IO.puts("\nPer-Agent Accuracy:")
per_agent
|> Enum.sort_by(fn {_agent, acc} -> -acc end)
|> Enum.each(fn {agent, acc} ->
  agent_name = agent |> to_string() |> String.replace("_", " ") |> String.capitalize()
  IO.puts("  #{String.pad_trailing(agent_name, 22)} #{Float.round(acc * 100, 1)}%")
end)

# ============================================================================
# 5. Disagreement Analysis
# ============================================================================

IO.puts("\n5. DISAGREEMENT ANALYSIS")
IO.puts("-" |> String.duplicate(40))

disagreement = CvlMetrics.disagreement_analysis(agent_predictions, nli_truth)

IO.puts("Samples with disagreement: #{disagreement.disagreement_count}")
IO.puts("Consensus accuracy on disagreements: #{Float.round(disagreement.consensus_accuracy * 100, 1)}%")

if disagreement.disagreement_count > 0 do
  IO.puts("\nPer-Agent Accuracy on Disagreement Cases:")
  disagreement.per_agent_accuracy
  |> Enum.sort_by(fn {_agent, acc} -> -acc end)
  |> Enum.each(fn {agent, acc} ->
    agent_name = agent |> to_string() |> String.replace("_", " ") |> String.capitalize()
    IO.puts("  #{String.pad_trailing(agent_name, 22)} #{Float.round(acc * 100, 1)}%")
  end)
end

# ============================================================================
# 6. Verdict Helper Functions
# ============================================================================

IO.puts("\n6. VERDICT CLASSIFICATION")
IO.puts("-" |> String.duplicate(40))

IO.puts("Valid CVL verdicts: #{inspect(CvlMetrics.valid_verdicts())}")
IO.puts("Flagged verdicts:   #{inspect(CvlMetrics.flagged_verdicts())}")

IO.puts("\nVerdict flagging examples:")
for verdict <- [:entailment, :contradiction, :neutral] do
  status = if CvlMetrics.flagged?(verdict), do: "FLAGGED", else: "NOT FLAGGED"
  IO.puts("  #{verdict} -> #{status}")
end

# ============================================================================
# Summary
# ============================================================================

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("CVL EVALUATION SUMMARY")
IO.puts(String.duplicate("=", 60))

format_pct = fn val -> (val * 100) |> Float.round(1) |> Float.to_string() |> String.pad_trailing(5) end
format_float = fn val -> val |> Float.round(3) |> Float.to_string() |> String.pad_trailing(7) end

IO.puts("")
IO.puts("Metric                          Value      Target    Status")
IO.puts("------------------------------  ---------  --------  ------")
IO.puts("Hallucination Recall            #{format_pct.(recall)}%    >95%      #{if recall >= 0.95, do: "PASS", else: "FAIL"}")
IO.puts("Hallucination Precision         #{format_pct.(precision)}%    >85%      #{if precision >= 0.85, do: "PASS", else: "FAIL"}")
IO.puts("Hallucination F1                #{format_float.(f1)}    -         -")
IO.puts("Agent Agreement Rate            #{format_pct.(agreement_rate)}%    >80%      #{if agreement_rate >= 0.80, do: "PASS", else: "FAIL"}")
IO.puts("Consensus Accuracy              #{format_pct.(consensus_acc)}%    -         -")
IO.puts("Calibration Error (ECE)         #{format_float.(ece)}    <0.1      #{if ece < 0.1, do: "PASS", else: "FAIL"}")
IO.puts("")

IO.puts("Example completed successfully!")
