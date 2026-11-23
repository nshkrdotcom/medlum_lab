# Medical Evaluation Example
#
# Run with: mix run examples/medical_evaluation.exs
#
# This example demonstrates MedlumLlm's medical evaluation metrics
# for benchmarking medical AI models.

alias MedlumLlm.Eval.MedicalMetrics

IO.puts("=" |> String.duplicate(60))
IO.puts("MedlumLlm Medical Evaluation Example")
IO.puts("=" |> String.duplicate(60))

# ============================================================================
# 1. MCQ Accuracy - Medical Question Answering
# ============================================================================

IO.puts("\n1. MCQ ACCURACY (MedQA/MedMCQA Style)")
IO.puts("-" |> String.duplicate(40))

# Simulated LLM predictions with various response formats
mcq_predictions = [
  %{predicted: "B", latency_ms: 150, output_tokens: 45},
  %{predicted: "The answer is A because hypertension is characterized by elevated blood pressure.", latency_ms: 280, output_tokens: 120},
  %{predicted: "C. Diabetes mellitus type 2 typically presents with polyuria and polydipsia.", latency_ms: 320, output_tokens: 135},
  %{predicted: "(D)", latency_ms: 95, output_tokens: 32},
  %{predicted: "Answer: A", latency_ms: 110, output_tokens: 38},
  %{predicted: "B. This patient most likely has acute pancreatitis given the epigastric pain radiating to the back.", latency_ms: 450, output_tokens: 180},
  %{predicted: "C", latency_ms: 85, output_tokens: 28},
  %{predicted: "The correct answer is D because the patient's symptoms are consistent with pneumonia.", latency_ms: 380, output_tokens: 155}
]

mcq_ground_truth = [
  %{correct_answer: "B"},
  %{correct_answer: "A"},
  %{correct_answer: "C"},
  %{correct_answer: "D"},
  %{correct_answer: "A"},
  %{correct_answer: "B"},
  %{correct_answer: "A"},  # Incorrect prediction
  %{correct_answer: "D"}
]

mcq_accuracy = MedicalMetrics.mcq_accuracy(mcq_predictions, mcq_ground_truth)
IO.puts("MCQ Accuracy: #{Float.round(mcq_accuracy * 100, 1)}%")

# Demonstrate answer extraction
IO.puts("\nAnswer Extraction Examples:")
examples = [
  "B",
  "The answer is C",
  "(D)",
  "A. Hypertension is...",
  "Answer: B"
]

for example <- examples do
  letter = MedicalMetrics.extract_answer_letter(example)
  IO.puts("  \"#{example}\" -> #{letter}")
end

# ============================================================================
# 2. Latency Percentiles
# ============================================================================

IO.puts("\n2. LATENCY PERCENTILES")
IO.puts("-" |> String.duplicate(40))

latency_stats = MedicalMetrics.latency_percentiles(mcq_predictions)

IO.puts("Sample Count: #{latency_stats.count}")
IO.puts("P50 (Median): #{Float.round(latency_stats.p50, 1)} ms")
IO.puts("P90:          #{Float.round(latency_stats.p90, 1)} ms")
IO.puts("P95:          #{Float.round(latency_stats.p95, 1)} ms")
IO.puts("P99:          #{Float.round(latency_stats.p99, 1)} ms")
IO.puts("Mean:         #{Float.round(latency_stats.mean, 1)} ms")
IO.puts("Min:          #{Float.round(latency_stats.min, 1)} ms")
IO.puts("Max:          #{Float.round(latency_stats.max, 1)} ms")

# ============================================================================
# 3. Tokens Per Second
# ============================================================================

IO.puts("\n3. TOKENS PER SECOND")
IO.puts("-" |> String.duplicate(40))

throughput = MedicalMetrics.tokens_per_second(mcq_predictions)
IO.puts("Throughput: #{Float.round(throughput, 1)} tokens/sec")

# ============================================================================
# 4. NLI Classification (Hallucination Detection)
# ============================================================================

IO.puts("\n4. NLI CLASSIFICATION (CVL/Hallucination Detection)")
IO.puts("-" |> String.duplicate(40))

nli_predictions = [
  %{predicted: "entailment"},
  %{predicted: "supports"},
  %{predicted: "e"},
  %{predicted: "contradiction"},
  %{predicted: "refutes"},
  %{predicted: "0"},
  %{predicted: "neutral"},
  %{predicted: "not_enough_info"},
  %{predicted: "entailment"}  # Incorrect - should be contradiction
]

nli_ground_truth = [
  %{label: "entailment"},
  %{label: "1"},
  %{label: "entail"},
  %{label: "contradiction"},
  %{label: "c"},
  %{label: "contradiction"},
  %{label: "neutral"},
  %{label: "2"},
  %{label: "contradiction"}
]

nli_accuracy = MedicalMetrics.nli_accuracy(nli_predictions, nli_ground_truth)
nli_f1 = MedicalMetrics.nli_macro_f1(nli_predictions, nli_ground_truth)

IO.puts("NLI Accuracy: #{Float.round(nli_accuracy * 100, 1)}%")
IO.puts("NLI Macro F1: #{Float.round(nli_f1, 3)}")

IO.puts("\nLabel Normalization Examples:")
labels = ["entailment", "supports", "e", "1", "contradiction", "refutes", "neutral", "nei"]
for label <- labels do
  normalized = MedicalMetrics.normalize_nli_label(label)
  IO.puts("  \"#{label}\" -> :#{normalized}")
end

# ============================================================================
# 5. Binary QA (PubMedQA Style)
# ============================================================================

IO.puts("\n5. BINARY QA (PubMedQA Style)")
IO.puts("-" |> String.duplicate(40))

pubmedqa_predictions = [
  %{predicted: "yes"},
  %{predicted: "Y"},
  %{predicted: "positive"},
  %{predicted: "no"},
  %{predicted: "n"},
  %{predicted: "maybe"},
  %{predicted: "uncertain"},
  %{predicted: "yes"}  # Incorrect - should be no
]

pubmedqa_ground_truth = [
  %{label: "yes"},
  %{label: "yes"},
  %{label: "1"},
  %{label: "no"},
  %{label: "0"},
  %{label: "maybe"},
  %{label: "m"},
  %{label: "no"}
]

qa_accuracy = MedicalMetrics.binary_qa_accuracy(pubmedqa_predictions, pubmedqa_ground_truth)
qa_f1 = MedicalMetrics.binary_qa_macro_f1(pubmedqa_predictions, pubmedqa_ground_truth)

IO.puts("Binary QA Accuracy: #{Float.round(qa_accuracy * 100, 1)}%")
IO.puts("Binary QA Macro F1: #{Float.round(qa_f1, 3)}")

# ============================================================================
# 6. Macro F1 Score (Multi-class)
# ============================================================================

IO.puts("\n6. MACRO F1 SCORE (Multi-class)")
IO.puts("-" |> String.duplicate(40))

# Imbalanced dataset example
multi_class_preds = [
  %{predicted: :class_a},
  %{predicted: :class_a},
  %{predicted: :class_a},
  %{predicted: :class_a},
  %{predicted: :class_b},
  %{predicted: :class_c}
]

multi_class_labels = [
  %{label: :class_a},
  %{label: :class_a},
  %{label: :class_a},
  %{label: :class_b},  # Misclassified
  %{label: :class_b},
  %{label: :class_c}
]

macro_f1 = MedicalMetrics.macro_f1(multi_class_preds, multi_class_labels)
IO.puts("Macro F1: #{Float.round(macro_f1, 3)}")

# Demonstrate weighted vs macro
IO.puts("\nNote: Macro F1 gives equal weight to each class,")
IO.puts("making it ideal for imbalanced medical datasets.")

# ============================================================================
# 7. Confusion Matrix
# ============================================================================

IO.puts("\n7. CONFUSION MATRIX")
IO.puts("-" |> String.duplicate(40))

matrix = MedicalMetrics.confusion_matrix(nli_predictions, nli_ground_truth, normalize: &MedicalMetrics.normalize_nli_label/1)

IO.puts("Classes: #{inspect(matrix.classes)}")
IO.puts("\nConfusion Matrix:")
IO.puts("                  Predicted")
IO.puts("              entail  contra  neutral")

for actual <- [:entailment, :contradiction, :neutral] do
  row = matrix.matrix[actual]
  e_count = Map.get(row, :entailment, 0)
  c_count = Map.get(row, :contradiction, 0)
  n_count = Map.get(row, :neutral, 0)

  label = actual |> to_string() |> String.slice(0..5) |> String.pad_trailing(8)
  IO.puts("Actual #{label}    #{e_count}       #{c_count}        #{n_count}")
end

# ============================================================================
# Summary
# ============================================================================

IO.puts("\n" <> "=" |> String.duplicate(60))
IO.puts("EVALUATION SUMMARY")
IO.puts("=" |> String.duplicate(60))

IO.puts("""

Metric                  Value
----------------------  --------
MCQ Accuracy            #{Float.round(mcq_accuracy * 100, 1)}%
NLI Accuracy            #{Float.round(nli_accuracy * 100, 1)}%
NLI Macro F1            #{Float.round(nli_f1, 3)}
Binary QA Accuracy      #{Float.round(qa_accuracy * 100, 1)}%
Binary QA Macro F1      #{Float.round(qa_f1, 3)}
Latency P50             #{Float.round(latency_stats.p50, 1)} ms
Latency P95             #{Float.round(latency_stats.p95, 1)} ms
Throughput              #{Float.round(throughput, 1)} tok/s
""")

IO.puts("Example completed successfully!")
