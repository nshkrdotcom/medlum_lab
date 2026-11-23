defmodule MedlumLlm.Eval.MedicalMetricsTest do
  use ExUnit.Case

  alias MedlumLlm.Eval.MedicalMetrics

  describe "accuracy/2" do
    test "calculates correct accuracy" do
      predictions = ["A", "B", "A", "C"]
      samples = [
        %{answer: "A"},
        %{answer: "B"},
        %{answer: "C"},
        %{answer: "C"}
      ]

      assert MedicalMetrics.accuracy(predictions, samples) == 0.75
    end

    test "returns 0.0 for all wrong" do
      predictions = ["A", "A"]
      samples = [%{answer: "B"}, %{answer: "C"}]

      assert MedicalMetrics.accuracy(predictions, samples) == 0.0
    end

    test "returns 1.0 for all correct" do
      predictions = ["A", "B", "C"]
      samples = [%{answer: "A"}, %{answer: "B"}, %{answer: "C"}]

      assert MedicalMetrics.accuracy(predictions, samples) == 1.0
    end

    test "handles string keys in samples" do
      predictions = ["A", "B"]
      samples = [%{"answer" => "A"}, %{"answer" => "B"}]

      assert MedicalMetrics.accuracy(predictions, samples) == 1.0
    end
  end

  describe "wilson_ci/3" do
    test "calculates Wilson confidence interval" do
      {low, high} = MedicalMetrics.wilson_ci(70, 100)

      assert low > 0.60
      assert low < 0.65
      assert high > 0.77
      assert high < 0.80
    end

    test "handles edge case of 0 successes" do
      {low, high} = MedicalMetrics.wilson_ci(0, 100)

      assert low >= 0.0
      assert high < 0.05
    end

    test "handles edge case of all successes" do
      {low, high} = MedicalMetrics.wilson_ci(100, 100)

      assert low > 0.95
      assert high <= 1.0
    end

    test "handles small sample size" do
      {low, high} = MedicalMetrics.wilson_ci(3, 5)

      # Wilson CI should work well with small samples
      assert low >= 0.0
      assert high <= 1.0
      assert low < high
    end
  end

  describe "medication_accuracy/2" do
    test "matches exact medication names" do
      predictions = [%{medications: [%{name: "metformin"}]}]
      samples = [%{medications: [%{name: "Metformin"}]}]

      assert MedicalMetrics.medication_accuracy(predictions, samples) == 1.0
    end

    test "returns 0.0 for no matches" do
      predictions = [%{medications: [%{name: "aspirin"}]}]
      samples = [%{medications: [%{name: "metformin"}]}]

      assert MedicalMetrics.medication_accuracy(predictions, samples) == 0.0
    end

    test "handles empty medications" do
      predictions = [%{medications: []}]
      samples = [%{medications: []}]

      assert MedicalMetrics.medication_accuracy(predictions, samples) == 0.0
    end

    test "handles partial matches across multiple samples" do
      predictions = [
        %{medications: [%{name: "metformin"}, %{name: "aspirin"}]},
        %{medications: [%{name: "lisinopril"}]}
      ]
      samples = [
        %{medications: [%{name: "metformin"}, %{name: "ibuprofen"}]},
        %{medications: [%{name: "lisinopril"}, %{name: "atorvastatin"}]}
      ]

      # 2 matches (metformin, lisinopril) out of 4 total gold (metformin, ibuprofen, lisinopril, atorvastatin)
      assert MedicalMetrics.medication_accuracy(predictions, samples) == 0.5
    end

    test "handles string keys in samples" do
      predictions = [%{"medications" => [%{"name" => "metformin"}]}]
      samples = [%{"medications" => [%{"name" => "Metformin"}]}]

      assert MedicalMetrics.medication_accuracy(predictions, samples) == 1.0
    end
  end

  describe "diagnosis_accuracy/2" do
    test "matches exact diagnosis names" do
      predictions = [%{diagnoses: [%{name: "diabetes"}]}]
      samples = [%{diagnoses: [%{name: "Diabetes"}]}]

      assert MedicalMetrics.diagnosis_accuracy(predictions, samples) == 1.0
    end

    test "matches by ICD-10 code when present" do
      predictions = [%{diagnoses: [%{icd10: "E11.9"}]}]
      samples = [%{diagnoses: [%{icd10: "E11.9", name: "Type 2 diabetes"}]}]

      assert MedicalMetrics.diagnosis_accuracy(predictions, samples) == 1.0
    end

    test "returns 0.0 for no matches" do
      predictions = [%{diagnoses: [%{name: "hypertension"}]}]
      samples = [%{diagnoses: [%{name: "diabetes"}]}]

      assert MedicalMetrics.diagnosis_accuracy(predictions, samples) == 0.0
    end

    test "handles empty diagnoses" do
      predictions = [%{diagnoses: []}]
      samples = [%{diagnoses: []}]

      assert MedicalMetrics.diagnosis_accuracy(predictions, samples) == 0.0
    end
  end

  describe "lab_accuracy/2" do
    test "matches exact lab names" do
      predictions = [%{labs: [%{name: "glucose"}]}]
      samples = [%{labs: [%{name: "Glucose"}]}]

      assert MedicalMetrics.lab_accuracy(predictions, samples) == 1.0
    end

    test "returns 0.0 for no matches" do
      predictions = [%{labs: [%{name: "hemoglobin"}]}]
      samples = [%{labs: [%{name: "glucose"}]}]

      assert MedicalMetrics.lab_accuracy(predictions, samples) == 0.0
    end

    test "handles empty labs" do
      predictions = [%{labs: []}]
      samples = [%{labs: []}]

      assert MedicalMetrics.lab_accuracy(predictions, samples) == 0.0
    end
  end

  describe "hallucination_recall/2" do
    test "calculates recall correctly" do
      cvl_predictions = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :entailment},
        %{sample_id: 3, verdict: :neutral}
      ]
      ground_truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true},
        %{sample_id: 3, is_hallucination: true}
      ]

      # 2 out of 3 caught (contradiction and neutral)
      assert MedicalMetrics.hallucination_recall(cvl_predictions, ground_truth) == 2/3
    end

    test "returns 1.0 when no hallucinations to detect" do
      cvl_predictions = [%{sample_id: 1, verdict: :entailment}]
      ground_truth = [%{sample_id: 1, is_hallucination: false}]

      assert MedicalMetrics.hallucination_recall(cvl_predictions, ground_truth) == 1.0
    end

    test "handles all hallucinations caught" do
      cvl_predictions = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :neutral}
      ]
      ground_truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true}
      ]

      assert MedicalMetrics.hallucination_recall(cvl_predictions, ground_truth) == 1.0
    end

    test "handles string keys" do
      cvl_predictions = [
        %{"sample_id" => 1, "verdict" => "contradiction"}
      ]
      ground_truth = [
        %{"sample_id" => 1, "is_hallucination" => true}
      ]

      assert MedicalMetrics.hallucination_recall(cvl_predictions, ground_truth) == 1.0
    end
  end

  describe "hallucination_precision/2" do
    test "calculates precision correctly" do
      cvl_predictions = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :contradiction}
      ]
      ground_truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: false}
      ]

      # 1 true positive out of 2 flagged
      assert MedicalMetrics.hallucination_precision(cvl_predictions, ground_truth) == 0.5
    end

    test "returns 1.0 when nothing flagged" do
      cvl_predictions = [
        %{sample_id: 1, verdict: :entailment}
      ]
      ground_truth = [
        %{sample_id: 1, is_hallucination: true}
      ]

      # Nothing flagged, trivially perfect precision
      assert MedicalMetrics.hallucination_precision(cvl_predictions, ground_truth) == 1.0
    end

    test "handles all flagged being true positives" do
      cvl_predictions = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :neutral}
      ]
      ground_truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true}
      ]

      assert MedicalMetrics.hallucination_precision(cvl_predictions, ground_truth) == 1.0
    end
  end

  describe "hallucination_f1/2" do
    test "calculates F1 as harmonic mean" do
      cvl_predictions = [
        %{sample_id: 1, verdict: :contradiction},
        %{sample_id: 2, verdict: :entailment},
        %{sample_id: 3, verdict: :contradiction}
      ]
      ground_truth = [
        %{sample_id: 1, is_hallucination: true},
        %{sample_id: 2, is_hallucination: true},
        %{sample_id: 3, is_hallucination: false}
      ]

      # Recall: 1/2 (only sample 1 caught, sample 2 missed)
      # Precision: 1/2 (sample 1 is TP, sample 3 is FP)
      # F1 = 2 * 0.5 * 0.5 / (0.5 + 0.5) = 0.5
      assert MedicalMetrics.hallucination_f1(cvl_predictions, ground_truth) == 0.5
    end

    test "returns 0.0 when both recall and precision are 0" do
      cvl_predictions = [
        %{sample_id: 1, verdict: :entailment}
      ]
      ground_truth = [
        %{sample_id: 2, is_hallucination: true}  # Different sample_id
      ]

      # No overlap, but no flagged items either, so precision is 1.0
      # But recall is 0 since the hallucination wasn't caught
      f1 = MedicalMetrics.hallucination_f1(cvl_predictions, ground_truth)
      assert f1 == 0.0
    end
  end

  describe "clinical_safety_score/3" do
    test "calculates weighted composite" do
      predictions = [%{medications: [%{name: "metformin"}], diagnoses: [%{name: "diabetes"}]}]
      samples = [%{medications: [%{name: "metformin"}], diagnoses: [%{name: "diabetes"}], sample_id: 1, is_hallucination: true}]
      cvl_results = [%{sample_id: 1, verdict: :contradiction}]

      # med_acc = 1.0, dx_acc = 1.0, hall_recall = 1.0
      # 0.4 * 1.0 + 0.3 * 1.0 + 0.3 * 1.0 = 1.0
      score = MedicalMetrics.clinical_safety_score(predictions, samples, cvl_results)
      assert_in_delta score, 1.0, 0.01
    end

    test "calculates with partial scores" do
      predictions = [
        %{medications: [%{name: "metformin"}], diagnoses: [%{name: "hypertension"}]}
      ]
      samples = [
        %{medications: [%{name: "metformin"}, %{name: "aspirin"}], diagnoses: [%{name: "diabetes"}], sample_id: 1, is_hallucination: true}
      ]
      cvl_results = [%{sample_id: 1, verdict: :entailment}]

      # med_acc = 0.5 (1 of 2), dx_acc = 0.0 (0 of 1), hall_recall = 0.0 (not caught)
      # 0.4 * 0.5 + 0.3 * 0.0 + 0.3 * 0.0 = 0.2
      score = MedicalMetrics.clinical_safety_score(predictions, samples, cvl_results)
      assert_in_delta score, 0.2, 0.01
    end
  end

  describe "format_report/3" do
    test "includes accuracy with CI" do
      predictions = ["A", "A", "B", "B"]
      samples = [
        %{answer: "A"},
        %{answer: "A"},
        %{answer: "A"},
        %{answer: "B"}
      ]

      report = MedicalMetrics.format_report(predictions, samples)

      assert report.accuracy == 0.75
      assert report.sample_count == 4
      assert report.correct_count == 3
      assert {low, high} = report.accuracy_ci_95
      assert low < 0.75
      assert high > 0.75
    end

    test "includes medical metrics when requested" do
      predictions = [%{answer: "A", medications: [%{name: "metformin"}], diagnoses: [%{name: "diabetes"}]}]
      samples = [%{answer: "A", medications: [%{name: "metformin"}], diagnoses: [%{name: "diabetes"}]}]

      report = MedicalMetrics.format_report(predictions, samples, medical_metrics: true)

      assert Map.has_key?(report, :medication_accuracy)
      assert Map.has_key?(report, :diagnosis_accuracy)
      assert report.medication_accuracy == 1.0
      assert report.diagnosis_accuracy == 1.0
    end
  end

  describe "exact_match/2" do
    test "returns 1.0 for exact matches" do
      predictions = ["hello", "world"]
      samples = [%{answer: "hello"}, %{answer: "world"}]

      assert MedicalMetrics.exact_match(predictions, samples) == 1.0
    end

    test "returns 0.0 for no matches" do
      predictions = ["hello", "world"]
      samples = [%{answer: "foo"}, %{answer: "bar"}]

      assert MedicalMetrics.exact_match(predictions, samples) == 0.0
    end

    test "handles whitespace trimming" do
      predictions = ["  hello  ", "world"]
      samples = [%{answer: "hello"}, %{answer: "  world  "}]

      assert MedicalMetrics.exact_match(predictions, samples) == 1.0
    end
  end

  describe "f1/3" do
    test "calculates F1 score" do
      predictions = ["A", "B", "A", "B"]
      samples = [
        %{answer: "A"},
        %{answer: "B"},
        %{answer: "B"},
        %{answer: "A"}
      ]

      # 2 correct out of 4 with some FPs and FNs
      f1 = MedicalMetrics.f1(predictions, samples)
      assert f1 >= 0.0
      assert f1 <= 1.0
    end
  end

  describe "mcnemar_test/3" do
    test "runs McNemar's test for paired comparison" do
      pred_a = ["A", "B", "A", "A", "B", "B"]
      pred_b = ["A", "A", "A", "B", "B", "A"]
      samples = [
        %{answer: "A"},
        %{answer: "B"},
        %{answer: "A"},
        %{answer: "A"},
        %{answer: "B"},
        %{answer: "B"}
      ]

      result = MedicalMetrics.mcnemar_test(pred_a, pred_b, samples)

      # Result should be a map with chi2 and p_value
      assert is_map(result)
      assert Map.has_key?(result, :chi2) or Map.has_key?(result, :statistic)
      assert Map.has_key?(result, :p_value)
    end
  end

  describe "bootstrap_ci/3" do
    test "returns interval tuple" do
      data = [1.0, 2.0, 3.0, 4.0, 5.0]
      stat_fn = fn d -> Enum.sum(d) / length(d) end

      {low, high} = MedicalMetrics.bootstrap_ci(data, stat_fn)

      assert is_float(low)
      assert is_float(high)
      assert low <= high
    end
  end

  # ============================================================================
  # MCQ Accuracy Tests (migrated from eval_ex)
  # ============================================================================

  describe "mcq_accuracy/2" do
    test "extracts single letter answer" do
      preds = [%{predicted: "B"}]
      samples = [%{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 1.0
    end

    test "extracts from verbose response 'The answer is X'" do
      preds = [%{predicted: "The answer is B because..."}]
      samples = [%{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 1.0
    end

    test "extracts from 'The correct answer is X'" do
      preds = [%{predicted: "The correct answer is C."}]
      samples = [%{correct_answer: "C"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 1.0
    end

    test "handles case insensitivity" do
      preds = [%{predicted: "b"}]
      samples = [%{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 1.0
    end

    test "handles parenthesized letter (B)" do
      preds = [%{predicted: "(B)"}]
      samples = [%{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 1.0
    end

    test "handles letter with period 'B.'" do
      preds = [%{predicted: "B."}]
      samples = [%{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 1.0
    end

    test "handles letter with explanation 'B. Diabetes mellitus is...'" do
      preds = [%{predicted: "B. Diabetes mellitus is a chronic condition."}]
      samples = [%{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 1.0
    end

    test "handles 'Answer: B' format" do
      preds = [%{predicted: "Answer: B"}]
      samples = [%{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 1.0
    end

    test "handles '[B]' format" do
      preds = [%{predicted: "[B]"}]
      samples = [%{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 1.0
    end

    test "handles 'Option B' format" do
      preds = [%{predicted: "Option B"}]
      samples = [%{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 1.0
    end

    test "returns 0.0 for incorrect answer" do
      preds = [%{predicted: "A"}]
      samples = [%{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 0.0
    end

    test "handles multiple samples" do
      preds = [
        %{predicted: "A"},
        %{predicted: "The answer is B"},
        %{predicted: "C"},
        %{predicted: "(D)"}
      ]

      samples = [
        %{correct_answer: "A"},
        %{correct_answer: "B"},
        %{correct_answer: "A"},
        %{correct_answer: "D"}
      ]

      # 3 correct out of 4
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 0.75
    end

    test "handles nil/empty responses gracefully" do
      preds = [%{predicted: nil}, %{predicted: ""}]
      samples = [%{correct_answer: "A"}, %{correct_answer: "B"}]
      assert MedicalMetrics.mcq_accuracy(preds, samples) == 0.0
    end

    test "returns 0.0 for empty inputs" do
      assert MedicalMetrics.mcq_accuracy([], []) == 0.0
    end
  end

  describe "extract_answer_letter/1" do
    test "extracts single letter" do
      assert MedicalMetrics.extract_answer_letter("B") == "B"
      assert MedicalMetrics.extract_answer_letter("a") == "A"
    end

    test "extracts from 'The answer is X'" do
      assert MedicalMetrics.extract_answer_letter("The answer is C") == "C"
    end

    test "extracts from parenthesized" do
      assert MedicalMetrics.extract_answer_letter("(D)") == "D"
      assert MedicalMetrics.extract_answer_letter("( A )") == "A"
    end

    test "extracts from 'Answer: X'" do
      assert MedicalMetrics.extract_answer_letter("Answer: B") == "B"
      assert MedicalMetrics.extract_answer_letter("Answer - C") == "C"
    end

    test "extracts from 'Option X'" do
      assert MedicalMetrics.extract_answer_letter("Option A") == "A"
      assert MedicalMetrics.extract_answer_letter("Choice B") == "B"
    end

    test "returns nil for invalid input" do
      assert MedicalMetrics.extract_answer_letter(nil) == nil
      assert MedicalMetrics.extract_answer_letter("") == nil
    end
  end

  # ============================================================================
  # Macro F1 Tests (migrated from eval_ex)
  # ============================================================================

  describe "macro_f1/3" do
    test "returns 1.0 for perfect predictions" do
      preds = [%{predicted: :yes}, %{predicted: :no}, %{predicted: :maybe}]
      samples = [%{label: :yes}, %{label: :no}, %{label: :maybe}]
      assert MedicalMetrics.macro_f1(preds, samples) == 1.0
    end

    test "returns 0.0 for completely wrong predictions" do
      preds = [%{predicted: :yes}]
      samples = [%{label: :no}]
      assert MedicalMetrics.macro_f1(preds, samples) == 0.0
    end

    test "calculates correct macro F1 for 3-class case" do
      # 2 correct yes, 1 incorrect no (should be yes)
      preds = [
        %{predicted: :yes},
        %{predicted: :yes},
        %{predicted: :no}
      ]

      samples = [
        %{label: :yes},
        %{label: :yes},
        %{label: :yes}
      ]

      # For class :yes: TP=2, FP=0, FN=1 -> P=1.0, R=2/3=0.667, F1=0.8
      # For class :no: TP=0, FP=1, FN=0 -> P=0.0, R=0.0 (no actual :no), F1=0.0
      # Macro F1 = (0.8 + 0.0) / 2 = 0.4
      result = MedicalMetrics.macro_f1(preds, samples)
      assert_in_delta result, 0.4, 0.01
    end

    test "handles explicit classes option" do
      preds = [%{predicted: :a}, %{predicted: :a}]
      samples = [%{label: :a}, %{label: :b}]

      result = MedicalMetrics.macro_f1(preds, samples, classes: [:a, :b, :c])

      # Class :a: TP=1, FP=1, FN=0 -> P=0.5, R=1.0, F1=0.667
      # Class :b: TP=0, FP=0, FN=1 -> P=0.0, R=0.0, F1=0.0
      # Class :c: TP=0, FP=0, FN=0 -> P=0.0, R=0.0, F1=0.0
      # Macro F1 = (0.667 + 0 + 0) / 3 = 0.222
      assert_in_delta result, 0.222, 0.01
    end

    test "handles normalize option" do
      preds = [%{predicted: "YES"}, %{predicted: "NO"}]
      samples = [%{label: "yes"}, %{label: "no"}]

      normalize = fn
        label when is_binary(label) -> String.downcase(label)
        label -> label
      end

      result = MedicalMetrics.macro_f1(preds, samples, normalize: normalize)
      assert result == 1.0
    end

    test "returns 0.0 for empty inputs" do
      assert MedicalMetrics.macro_f1([], []) == 0.0
    end
  end

  # ============================================================================
  # NLI Accuracy Tests (migrated from eval_ex)
  # ============================================================================

  describe "nli_accuracy/2" do
    test "handles standard labels" do
      preds = [%{predicted: "entailment"}, %{predicted: "contradiction"}]
      samples = [%{label: "entailment"}, %{label: "contradiction"}]
      assert MedicalMetrics.nli_accuracy(preds, samples) == 1.0
    end

    test "handles short labels" do
      preds = [%{predicted: "e"}, %{predicted: "c"}, %{predicted: "n"}]
      samples = [%{label: "entailment"}, %{label: "contradiction"}, %{label: "neutral"}]
      assert MedicalMetrics.nli_accuracy(preds, samples) == 1.0
    end

    test "handles numeric labels" do
      preds = [%{predicted: "1"}, %{predicted: "0"}, %{predicted: "2"}]
      samples = [%{label: "1"}, %{label: "0"}, %{label: "2"}]
      assert MedicalMetrics.nli_accuracy(preds, samples) == 1.0
    end

    test "handles alternative labels" do
      preds = [%{predicted: "supports"}, %{predicted: "refutes"}, %{predicted: "not_enough_info"}]

      samples = [
        %{label: "entailment"},
        %{label: "contradiction"},
        %{label: "neutral"}
      ]

      assert MedicalMetrics.nli_accuracy(preds, samples) == 1.0
    end

    test "handles atom labels" do
      preds = [%{predicted: :entailment}, %{predicted: :contradiction}]
      samples = [%{label: :entailment}, %{label: :contradiction}]
      assert MedicalMetrics.nli_accuracy(preds, samples) == 1.0
    end

    test "handles integer labels" do
      preds = [%{predicted: 1}, %{predicted: 0}]
      samples = [%{label: 1}, %{label: 0}]
      assert MedicalMetrics.nli_accuracy(preds, samples) == 1.0
    end

    test "returns 0.0 for incorrect predictions" do
      preds = [%{predicted: "entailment"}]
      samples = [%{label: "contradiction"}]
      assert MedicalMetrics.nli_accuracy(preds, samples) == 0.0
    end

    test "returns 0.0 for unknown labels" do
      preds = [%{predicted: "invalid"}]
      samples = [%{label: "invalid"}]
      assert MedicalMetrics.nli_accuracy(preds, samples) == 0.0
    end
  end

  describe "normalize_nli_label/1" do
    test "normalizes entailment variants" do
      assert MedicalMetrics.normalize_nli_label("entailment") == :entailment
      assert MedicalMetrics.normalize_nli_label("entail") == :entailment
      assert MedicalMetrics.normalize_nli_label("e") == :entailment
      assert MedicalMetrics.normalize_nli_label("1") == :entailment
      assert MedicalMetrics.normalize_nli_label("supports") == :entailment
      assert MedicalMetrics.normalize_nli_label("true") == :entailment
    end

    test "normalizes contradiction variants" do
      assert MedicalMetrics.normalize_nli_label("contradiction") == :contradiction
      assert MedicalMetrics.normalize_nli_label("contradict") == :contradiction
      assert MedicalMetrics.normalize_nli_label("c") == :contradiction
      assert MedicalMetrics.normalize_nli_label("0") == :contradiction
      assert MedicalMetrics.normalize_nli_label("refutes") == :contradiction
      assert MedicalMetrics.normalize_nli_label("false") == :contradiction
    end

    test "normalizes neutral variants" do
      assert MedicalMetrics.normalize_nli_label("neutral") == :neutral
      assert MedicalMetrics.normalize_nli_label("n") == :neutral
      assert MedicalMetrics.normalize_nli_label("2") == :neutral
      assert MedicalMetrics.normalize_nli_label("not_enough_info") == :neutral
      assert MedicalMetrics.normalize_nli_label("nei") == :neutral
      assert MedicalMetrics.normalize_nli_label("maybe") == :neutral
    end

    test "normalizes atom inputs" do
      assert MedicalMetrics.normalize_nli_label(:entailment) == :entailment
      assert MedicalMetrics.normalize_nli_label(:contradiction) == :contradiction
      assert MedicalMetrics.normalize_nli_label(:neutral) == :neutral
    end

    test "normalizes integer inputs" do
      assert MedicalMetrics.normalize_nli_label(1) == :entailment
      assert MedicalMetrics.normalize_nli_label(0) == :contradiction
      assert MedicalMetrics.normalize_nli_label(2) == :neutral
    end

    test "returns :unknown for unrecognized labels" do
      assert MedicalMetrics.normalize_nli_label("invalid") == :unknown
      assert MedicalMetrics.normalize_nli_label(:invalid) == :unknown
      assert MedicalMetrics.normalize_nli_label(99) == :unknown
    end
  end

  describe "nli_macro_f1/2" do
    test "calculates macro F1 for NLI classification" do
      preds = [
        %{predicted: "entailment"},
        %{predicted: "entailment"},
        %{predicted: "contradiction"}
      ]

      samples = [
        %{label: "entailment"},
        %{label: "contradiction"},
        %{label: "contradiction"}
      ]

      result = MedicalMetrics.nli_macro_f1(preds, samples)
      # entailment: TP=1, FP=1, FN=0 -> P=0.5, R=1.0, F1=0.667
      # contradiction: TP=1, FP=0, FN=1 -> P=1.0, R=0.5, F1=0.667
      # neutral: TP=0, FP=0, FN=0 -> F1=0.0
      # Macro F1 = (0.667 + 0.667 + 0) / 3 = 0.444
      assert_in_delta result, 0.444, 0.01
    end
  end

  # ============================================================================
  # Binary QA Accuracy Tests (migrated from eval_ex)
  # ============================================================================

  describe "binary_qa_accuracy/2" do
    test "handles standard yes/no/maybe labels" do
      preds = [%{predicted: "yes"}, %{predicted: "no"}, %{predicted: "maybe"}]
      samples = [%{label: "yes"}, %{label: "no"}, %{label: "maybe"}]
      assert MedicalMetrics.binary_qa_accuracy(preds, samples) == 1.0
    end

    test "handles short labels" do
      preds = [%{predicted: "y"}, %{predicted: "n"}, %{predicted: "m"}]
      samples = [%{label: "yes"}, %{label: "no"}, %{label: "maybe"}]
      assert MedicalMetrics.binary_qa_accuracy(preds, samples) == 1.0
    end

    test "handles case insensitivity" do
      preds = [%{predicted: "YES"}, %{predicted: "No"}]
      samples = [%{label: "yes"}, %{label: "no"}]
      assert MedicalMetrics.binary_qa_accuracy(preds, samples) == 1.0
    end

    test "handles alternative labels" do
      preds = [%{predicted: "uncertain"}, %{predicted: "positive"}]
      samples = [%{label: "maybe"}, %{label: "yes"}]
      assert MedicalMetrics.binary_qa_accuracy(preds, samples) == 1.0
    end

    test "returns 0.0 for incorrect predictions" do
      preds = [%{predicted: "yes"}]
      samples = [%{label: "no"}]
      assert MedicalMetrics.binary_qa_accuracy(preds, samples) == 0.0
    end
  end

  describe "normalize_binary_qa_label/1" do
    test "normalizes yes variants" do
      assert MedicalMetrics.normalize_binary_qa_label("yes") == :yes
      assert MedicalMetrics.normalize_binary_qa_label("y") == :yes
      assert MedicalMetrics.normalize_binary_qa_label("true") == :yes
      assert MedicalMetrics.normalize_binary_qa_label("1") == :yes
      assert MedicalMetrics.normalize_binary_qa_label("positive") == :yes
    end

    test "normalizes no variants" do
      assert MedicalMetrics.normalize_binary_qa_label("no") == :no
      assert MedicalMetrics.normalize_binary_qa_label("n") == :no
      assert MedicalMetrics.normalize_binary_qa_label("false") == :no
      assert MedicalMetrics.normalize_binary_qa_label("0") == :no
      assert MedicalMetrics.normalize_binary_qa_label("negative") == :no
    end

    test "normalizes maybe variants" do
      assert MedicalMetrics.normalize_binary_qa_label("maybe") == :maybe
      assert MedicalMetrics.normalize_binary_qa_label("m") == :maybe
      assert MedicalMetrics.normalize_binary_qa_label("uncertain") == :maybe
      assert MedicalMetrics.normalize_binary_qa_label("cannot determine") == :maybe
    end

    test "handles atom inputs" do
      assert MedicalMetrics.normalize_binary_qa_label(:yes) == :yes
      assert MedicalMetrics.normalize_binary_qa_label(:no) == :no
      assert MedicalMetrics.normalize_binary_qa_label(:maybe) == :maybe
    end

    test "handles integer inputs" do
      assert MedicalMetrics.normalize_binary_qa_label(1) == :yes
      assert MedicalMetrics.normalize_binary_qa_label(0) == :no
      assert MedicalMetrics.normalize_binary_qa_label(2) == :maybe
    end
  end

  describe "binary_qa_macro_f1/2" do
    test "calculates macro F1 for binary QA" do
      preds = [%{predicted: "yes"}, %{predicted: "yes"}, %{predicted: "no"}]
      samples = [%{label: "yes"}, %{label: "no"}, %{label: "no"}]

      result = MedicalMetrics.binary_qa_macro_f1(preds, samples)
      # yes: TP=1, FP=1, FN=0 -> P=0.5, R=1.0, F1=0.667
      # no: TP=1, FP=0, FN=1 -> P=1.0, R=0.5, F1=0.667
      # maybe: TP=0, FP=0, FN=0 -> F1=0.0
      # Macro F1 = (0.667 + 0.667 + 0) / 3 = 0.444
      assert_in_delta result, 0.444, 0.01
    end
  end

  # ============================================================================
  # Latency Percentiles Tests (migrated from eval_ex)
  # ============================================================================

  describe "latency_percentiles/1" do
    test "calculates percentiles correctly" do
      # Create 100 samples with sequential latencies 1-100
      preds = Enum.map(1..100, fn i -> %{latency_ms: i} end)

      result = MedicalMetrics.latency_percentiles(preds)

      assert_in_delta result.p50, 50.5, 1.0
      assert_in_delta result.p90, 90.1, 1.0
      assert_in_delta result.p95, 95.05, 1.0
      assert_in_delta result.p99, 99.01, 1.0
      assert_in_delta result.mean, 50.5, 0.1
      assert result.min == 1.0
      assert result.max == 100.0
      assert result.count == 100
    end

    test "handles small sample set" do
      preds = [%{latency_ms: 100}, %{latency_ms: 200}, %{latency_ms: 300}]

      result = MedicalMetrics.latency_percentiles(preds)

      assert result.p50 == 200.0
      # With 3 samples and linear interpolation:
      # P90: index = 0.9 * 2 = 1.8, interpolates between 200 and 300
      assert_in_delta result.p90, 280.0, 1.0
      assert_in_delta result.p95, 290.0, 1.0
      assert_in_delta result.p99, 298.0, 1.0
      assert_in_delta result.mean, 200.0, 0.1
      assert result.min == 100.0
      assert result.max == 300.0
      assert result.count == 3
    end

    test "handles single sample" do
      preds = [%{latency_ms: 150}]

      result = MedicalMetrics.latency_percentiles(preds)

      assert result.p50 == 150.0
      assert result.p90 == 150.0
      assert result.p95 == 150.0
      assert result.p99 == 150.0
      assert result.mean == 150.0
      assert result.count == 1
    end

    test "handles empty input" do
      result = MedicalMetrics.latency_percentiles([])

      assert result.p50 == 0.0
      assert result.p90 == 0.0
      assert result.mean == 0.0
      assert result.count == 0
    end

    test "filters out non-numeric latencies" do
      preds = [
        %{latency_ms: 100},
        %{latency_ms: nil},
        %{latency_ms: 200},
        %{other_field: 500}
      ]

      result = MedicalMetrics.latency_percentiles(preds)

      assert result.count == 2
      assert result.mean == 150.0
    end

    test "handles integer and float latencies" do
      preds = [%{latency_ms: 100}, %{latency_ms: 200.5}]

      result = MedicalMetrics.latency_percentiles(preds)

      assert result.count == 2
      assert_in_delta result.mean, 150.25, 0.01
    end
  end

  # ============================================================================
  # Tokens Per Second Tests (migrated from eval_ex)
  # ============================================================================

  describe "tokens_per_second/1" do
    test "calculates throughput correctly" do
      preds = [
        %{output_tokens: 100, latency_ms: 1000},
        %{output_tokens: 200, latency_ms: 2000}
      ]

      # Total: 300 tokens in 3 seconds = 100 tokens/sec
      assert MedicalMetrics.tokens_per_second(preds) == 100.0
    end

    test "handles single prediction" do
      preds = [%{output_tokens: 50, latency_ms: 500}]

      # 50 tokens in 0.5 seconds = 100 tokens/sec
      assert MedicalMetrics.tokens_per_second(preds) == 100.0
    end

    test "returns 0.0 for empty input" do
      assert MedicalMetrics.tokens_per_second([]) == 0.0
    end

    test "returns 0.0 when no valid data" do
      preds = [%{other_field: 123}]
      assert MedicalMetrics.tokens_per_second(preds) == 0.0
    end

    test "filters out non-numeric values" do
      preds = [
        %{output_tokens: 100, latency_ms: 1000},
        %{output_tokens: nil, latency_ms: 500},
        %{output_tokens: 50, latency_ms: nil}
      ]

      # Only first prediction is valid: 100 tokens in 1 second
      assert MedicalMetrics.tokens_per_second(preds) == 100.0
    end

    test "handles high throughput" do
      preds = [%{output_tokens: 1000, latency_ms: 100}]

      # 1000 tokens in 0.1 seconds = 10_000 tokens/sec
      assert MedicalMetrics.tokens_per_second(preds) == 10_000.0
    end
  end

  # ============================================================================
  # Confusion Matrix Tests (migrated from eval_ex)
  # ============================================================================

  describe "confusion_matrix/3" do
    test "builds correct matrix for binary classification" do
      preds = [%{predicted: :a}, %{predicted: :b}, %{predicted: :a}, %{predicted: :b}]
      samples = [%{label: :a}, %{label: :a}, %{label: :b}, %{label: :b}]

      result = MedicalMetrics.confusion_matrix(preds, samples)

      assert result.matrix[:a][:a] == 1
      assert result.matrix[:a][:b] == 1
      assert result.matrix[:b][:a] == 1
      assert result.matrix[:b][:b] == 1
    end

    test "calculates totals correctly" do
      preds = [%{predicted: :a}, %{predicted: :a}, %{predicted: :b}]
      samples = [%{label: :a}, %{label: :b}, %{label: :b}]

      result = MedicalMetrics.confusion_matrix(preds, samples)

      assert result.totals[:a].actual == 1
      assert result.totals[:a].predicted == 2
      assert result.totals[:b].actual == 2
      assert result.totals[:b].predicted == 1
    end

    test "handles explicit classes" do
      preds = [%{predicted: :a}]
      samples = [%{label: :a}]

      result = MedicalMetrics.confusion_matrix(preds, samples, classes: [:a, :b, :c])

      assert :a in result.classes
      assert :b in result.classes
      assert :c in result.classes
      assert result.matrix[:b][:b] == 0
    end

    test "handles normalize option" do
      preds = [%{predicted: "YES"}]
      samples = [%{label: "yes"}]

      normalize = &String.downcase/1

      result = MedicalMetrics.confusion_matrix(preds, samples, normalize: normalize)

      assert result.matrix["yes"]["yes"] == 1
    end
  end
end
