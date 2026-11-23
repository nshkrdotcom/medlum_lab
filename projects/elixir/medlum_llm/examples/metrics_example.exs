#!/usr/bin/env elixir
# Medical Metrics Examples for MedlumLlm
#
# Run with: mix run examples/metrics_example.exs

alias MedlumLlm.Eval.MedicalMetrics

IO.puts("=== MedlumLlm Medical Metrics Example ===\n")

# -----------------------------------------------------------------------------
# 1. Basic Accuracy Calculation
# -----------------------------------------------------------------------------

IO.puts("1. Basic Accuracy:")

predictions = ["A", "B", "C", "A", "D", "B", "C", "A", "B", "C"]
samples = [
  %{answer: "A"},  # correct
  %{answer: "B"},  # correct
  %{answer: "A"},  # wrong (predicted C)
  %{answer: "A"},  # correct
  %{answer: "D"},  # correct
  %{answer: "C"},  # wrong (predicted B)
  %{answer: "C"},  # correct
  %{answer: "B"},  # wrong (predicted A)
  %{answer: "B"},  # correct
  %{answer: "C"}   # correct
]

accuracy = MedicalMetrics.accuracy(predictions, samples)
IO.puts("   Predictions: #{inspect(predictions)}")
IO.puts("   Accuracy: #{Float.round(accuracy * 100, 1)}% (7/10 correct)")
IO.puts("")

# -----------------------------------------------------------------------------
# 2. Wilson Confidence Interval
# -----------------------------------------------------------------------------

IO.puts("2. Wilson Confidence Interval:")

correct = 7
total = 10

{lower, upper} = MedicalMetrics.wilson_ci(correct, total)
IO.puts("   Correct: #{correct}/#{total}")
IO.puts("   95% CI: [#{Float.round(lower * 100, 1)}%, #{Float.round(upper * 100, 1)}%]")
IO.puts("   Interpretation: We can be 95% confident the true accuracy")
IO.puts("                   lies between #{Float.round(lower * 100, 1)}% and #{Float.round(upper * 100, 1)}%")
IO.puts("")

# Different sample sizes show CI width
IO.puts("   CI width vs sample size:")
for {n, k} <- [{10, 7}, {50, 35}, {100, 70}, {500, 350}, {1000, 700}] do
  {l, u} = MedicalMetrics.wilson_ci(k, n)
  width = Float.round((u - l) * 100, 1)
  IO.puts("     n=#{n}: #{Float.round(k/n * 100, 1)}% +/- #{Float.round(width / 2, 1)}%")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 3. F1 Score
# -----------------------------------------------------------------------------

IO.puts("3. F1 Score:")

# Binary classification scenario
binary_predictions = ["positive", "negative", "positive", "positive", "negative", "negative"]
binary_samples = [
  %{answer: "positive"},   # TP
  %{answer: "negative"},   # TN
  %{answer: "negative"},   # FP
  %{answer: "positive"},   # TP
  %{answer: "positive"},   # FN
  %{answer: "negative"}    # TN
]

f1 = MedicalMetrics.f1(binary_predictions, binary_samples)
IO.puts("   F1 Score: #{Float.round(f1, 3)}")
IO.puts("   (Harmonic mean of precision and recall)")
IO.puts("")

# -----------------------------------------------------------------------------
# 4. Exact Match
# -----------------------------------------------------------------------------

IO.puts("4. Exact Match:")

generated = ["hypertension", "Diabetes Mellitus", "CHF"]
reference = [
  %{answer: "hypertension"},
  %{answer: "diabetes mellitus"},  # case difference
  %{answer: "congestive heart failure"}  # abbreviation
]

em = MedicalMetrics.exact_match(generated, reference)
IO.puts("   Generated: #{inspect(generated)}")
IO.puts("   Reference: #{inspect(Enum.map(reference, & &1.answer))}")
IO.puts("   Exact Match: #{Float.round(em * 100, 1)}%")
IO.puts("   Note: Only 'hypertension' matches exactly")
IO.puts("")

# -----------------------------------------------------------------------------
# 5. CVL Hallucination Metrics
# -----------------------------------------------------------------------------

IO.puts("5. CVL Hallucination Detection Metrics:")

# CVL results with sample IDs
cvl_predictions = [
  %{sample_id: "s1", verdict: :contradiction},  # Flagged - TP
  %{sample_id: "s2", verdict: :entailment},     # Not flagged
  %{sample_id: "s3", verdict: :neutral},        # Flagged (uncertain) - FP
  %{sample_id: "s4", verdict: :contradiction},  # Flagged - TP
  %{sample_id: "s5", verdict: :entailment}      # Not flagged - FN
]

# Ground truth - which ones are actually hallucinations
ground_truth = [
  %{sample_id: "s1", is_hallucination: true},   # True hallucination
  %{sample_id: "s2", is_hallucination: false},  # Not a hallucination
  %{sample_id: "s3", is_hallucination: false},  # Not a hallucination
  %{sample_id: "s4", is_hallucination: true},   # True hallucination
  %{sample_id: "s5", is_hallucination: true}    # True hallucination (missed!)
]

recall = MedicalMetrics.hallucination_recall(cvl_predictions, ground_truth)
precision = MedicalMetrics.hallucination_precision(cvl_predictions, ground_truth)
f1 = MedicalMetrics.hallucination_f1(cvl_predictions, ground_truth)

IO.puts("   CVL Verdicts: contradiction, entailment, neutral, contradiction, entailment")
IO.puts("   True Status:  hallucination, safe, safe, hallucination, hallucination")
IO.puts("")
IO.puts("   Hallucination Recall: #{Float.round(recall * 100, 1)}%")
IO.puts("   (What fraction of actual hallucinations did CVL catch?)")
IO.puts("")
IO.puts("   Hallucination Precision: #{Float.round(precision * 100, 1)}%")
IO.puts("   (What fraction of CVL flags were actual hallucinations?)")
IO.puts("")
IO.puts("   Hallucination F1: #{Float.round(f1, 3)}")
IO.puts("")
IO.puts("   Grant Target: >95% recall, >85% precision")
IO.puts("")

# -----------------------------------------------------------------------------
# 6. Medical-Specific Metrics: Medication Accuracy
# -----------------------------------------------------------------------------

IO.puts("6. Medication Accuracy:")

medication_predictions = [
  %{medications: [%{name: "metformin"}, %{name: "lisinopril"}]},
  %{medications: [%{name: "aspirin"}]},
  %{medications: [%{name: "atorvastatin"}, %{name: "amlodipine"}]}
]

medication_samples = [
  %{medications: [%{name: "metformin"}, %{name: "lisinopril"}]},  # 2/2 correct
  %{medications: [%{name: "aspirin"}, %{name: "warfarin"}]},       # 1/2 correct
  %{medications: [%{name: "atorvastatin"}]}                         # 1/1 correct
]

med_accuracy = MedicalMetrics.medication_accuracy(medication_predictions, medication_samples)
IO.puts("   Medication Accuracy: #{Float.round(med_accuracy * 100, 1)}%")
IO.puts("   (4/5 gold medications matched by predictions)")
IO.puts("")

# -----------------------------------------------------------------------------
# 7. Medical-Specific Metrics: Diagnosis Accuracy
# -----------------------------------------------------------------------------

IO.puts("7. Diagnosis Accuracy:")

diagnosis_predictions = [
  %{diagnoses: [%{name: "type 2 diabetes"}, %{name: "hypertension"}]},
  %{diagnoses: [%{name: "pneumonia"}]}
]

diagnosis_samples = [
  %{diagnoses: [%{name: "type 2 diabetes"}, %{name: "hypertension"}, %{name: "obesity"}]},
  %{diagnoses: [%{name: "pneumonia"}]}
]

dx_accuracy = MedicalMetrics.diagnosis_accuracy(diagnosis_predictions, diagnosis_samples)
IO.puts("   Diagnosis Accuracy: #{Float.round(dx_accuracy * 100, 1)}%")
IO.puts("   (3/4 gold diagnoses matched by predictions)")
IO.puts("")

# -----------------------------------------------------------------------------
# 8. McNemar Test (Model Comparison)
# -----------------------------------------------------------------------------

IO.puts("8. McNemar Test (Comparing Two Models):")

# Comparing Model A vs Model B on same test set
# We need predictions from both models on identical samples
pred_a = ["A", "B", "A", "C", "D", "A", "B", "C", "A", "D"]
pred_b = ["A", "A", "A", "C", "D", "B", "B", "C", "B", "D"]
samples_test = [
  %{answer: "A"},  # Both correct
  %{answer: "B"},  # A correct, B wrong
  %{answer: "A"},  # Both correct
  %{answer: "C"},  # Both correct
  %{answer: "D"},  # Both correct
  %{answer: "A"},  # A correct, B wrong
  %{answer: "B"},  # Both correct
  %{answer: "C"},  # Both correct
  %{answer: "A"},  # A correct, B wrong
  %{answer: "D"}   # Both correct
]

result = MedicalMetrics.mcnemar_test(pred_a, pred_b, samples_test)
IO.puts("   Model A accuracy: #{Float.round(MedicalMetrics.accuracy(pred_a, samples_test) * 100, 1)}%")
IO.puts("   Model B accuracy: #{Float.round(MedicalMetrics.accuracy(pred_b, samples_test) * 100, 1)}%")
IO.puts("")
IO.puts("   McNemar Test Results:")
IO.puts("     Chi-squared: #{Float.round(result.chi2, 3)}")
IO.puts("     P-value: #{Float.round(result.p_value, 4)}")

if result.significant do
  IO.puts("     Conclusion: Models have SIGNIFICANTLY different error patterns (p < 0.05)")
else
  IO.puts("     Conclusion: No significant difference in error patterns (p >= 0.05)")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 9. Format Report with CI
# -----------------------------------------------------------------------------

IO.puts("9. Formatted Evaluation Report:")

report = MedicalMetrics.format_report(predictions, samples)
IO.puts("   Sample Count: #{report.sample_count}")
IO.puts("   Correct Count: #{report.correct_count}")
IO.puts("   Accuracy: #{Float.round(report.accuracy * 100, 1)}%")
{ci_low, ci_high} = report.accuracy_ci_95
IO.puts("   95% CI: [#{Float.round(ci_low * 100, 1)}%, #{Float.round(ci_high * 100, 1)}%]")
IO.puts("")

# -----------------------------------------------------------------------------
# 10. Bootstrap Confidence Interval
# -----------------------------------------------------------------------------

IO.puts("10. Bootstrap Confidence Interval (Advanced):")

# Sample data - latencies in milliseconds
latencies = [120, 145, 132, 189, 156, 201, 178, 143, 167, 195,
             142, 158, 175, 183, 168, 149, 191, 162, 177, 154]

mean_latency = Enum.sum(latencies) / length(latencies)
IO.puts("   Sample latencies (ms): #{length(latencies)} observations")
IO.puts("   Mean latency: #{Float.round(mean_latency, 1)}ms")

# Simple percentiles
sorted = Enum.sort(latencies)
p50 = Enum.at(sorted, div(length(sorted), 2))
p95_idx = round(length(sorted) * 0.95) - 1
p95 = Enum.at(sorted, p95_idx)

IO.puts("   P50 (median): #{p50}ms")
IO.puts("   P95: #{p95}ms")
IO.puts("")

# -----------------------------------------------------------------------------
# 11. Clinical Safety Score
# -----------------------------------------------------------------------------

IO.puts("11. Clinical Safety Score (Composite):")
IO.puts("   Formula: 0.4 * med_acc + 0.3 * dx_acc + 0.3 * hallucination_recall")
IO.puts("")
IO.puts("   Weights rationale:")
IO.puts("     - Medication (40%): Most safety-critical")
IO.puts("     - Diagnosis (30%): Important for treatment decisions")
IO.puts("     - Hallucination Detection (30%): Prevents misinformation")
IO.puts("")

# Example calculation
med_acc = 0.85
dx_acc = 0.80
hall_recall = 0.95

safety_score = 0.4 * med_acc + 0.3 * dx_acc + 0.3 * hall_recall
IO.puts("   Example:")
IO.puts("     Medication Accuracy: #{Float.round(med_acc * 100, 1)}%")
IO.puts("     Diagnosis Accuracy: #{Float.round(dx_acc * 100, 1)}%")
IO.puts("     Hallucination Recall: #{Float.round(hall_recall * 100, 1)}%")
IO.puts("     Clinical Safety Score: #{Float.round(safety_score, 3)}")
IO.puts("")
IO.puts("   Grant Target: Safety Score > 0.85")
IO.puts("")

IO.puts("=== Metrics Examples Complete ===")
