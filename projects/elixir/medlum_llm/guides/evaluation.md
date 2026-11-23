# Medical Evaluation

This guide covers evaluating medical LLMs using MedlumLlm.

## Overview

MedlumLlm provides medical-specific evaluation metrics that extend the standard NSAI evaluation stack. The metrics are designed to:

- Measure clinical accuracy beyond simple text matching
- Validate against medical ontologies (RxNorm, ICD-10, LOINC)
- Detect hallucinations using CVL (Clinical Verification Layer)
- Support reproducible clinical validation benchmarks

## Metrics

### Standard Metrics

Standard metrics are delegated from `eval_ex`:

```elixir
alias MedlumLlm.Eval.MedicalMetrics

# Basic accuracy
predictions = ["A", "B", "C", "D"]
samples = [%{answer: "A"}, %{answer: "B"}, %{answer: "A"}, %{answer: "D"}]

acc = MedicalMetrics.accuracy(predictions, samples)
#=> 0.75

# Exact match (with normalization)
MedicalMetrics.exact_match(["hello world"], [%{answer: "Hello World"}])
#=> 1.0

# F1 score
MedicalMetrics.f1(predictions, samples)
#=> 0.75
```

### Confidence Intervals

Use Wilson score intervals for reliable confidence bounds, especially with small samples:

```elixir
# 70 correct out of 100 predictions, 95% CI
{low, high} = MedicalMetrics.wilson_ci(70, 100)
#=> {0.602, 0.785}

# Works well with small samples (unlike normal approximation)
{low, high} = MedicalMetrics.wilson_ci(3, 5)
#=> {0.187, 0.905}
```

### Medical-Specific Metrics

#### Medication Accuracy (RxNorm validation)

Measures what fraction of predicted medications match the ground truth:

```elixir
predictions = [
  %{medications: [%{name: "metformin"}, %{name: "aspirin"}]}
]
samples = [
  %{medications: [%{name: "Metformin"}, %{name: "Lisinopril"}]}
]

med_acc = MedicalMetrics.medication_accuracy(predictions, samples)
#=> 0.5  # metformin matches, aspirin doesn't, lisinopril missed
```

When `clinical_ner_ex` is available, entities are extracted from text:

```elixir
predictions = [%{text: "Patient should take metformin 500mg twice daily"}]
samples = [%{medications: [%{name: "metformin", dose: "500mg"}]}]

MedicalMetrics.medication_accuracy(predictions, samples)
#=> 1.0
```

#### Diagnosis Accuracy (ICD-10 validation)

Measures what fraction of predicted diagnoses are valid ICD-10 codes matching ground truth:

```elixir
predictions = [
  %{diagnoses: [%{icd10: "E11.9"}, %{name: "hypertension"}]}
]
samples = [
  %{diagnoses: [%{icd10: "E11.9", name: "Type 2 diabetes"}, %{name: "CHF"}]}
]

dx_acc = MedicalMetrics.diagnosis_accuracy(predictions, samples)
#=> 0.5  # E11.9 matches, hypertension doesn't match CHF
```

#### Lab Accuracy (LOINC validation)

Measures what fraction of lab values match:

```elixir
predictions = [%{labs: [%{name: "glucose"}, %{name: "hemoglobin"}]}]
samples = [%{labs: [%{name: "Glucose"}, %{name: "HbA1c"}]}]

lab_acc = MedicalMetrics.lab_accuracy(predictions, samples)
#=> 0.5
```

### Hallucination Detection

#### Hallucination Recall

Measures what fraction of actual hallucinations were detected by CVL:

```elixir
cvl_predictions = [
  %{sample_id: 1, verdict: :contradiction},  # Flagged correctly
  %{sample_id: 2, verdict: :entailment},     # Missed
  %{sample_id: 3, verdict: :neutral}         # Flagged correctly (triggers review)
]
ground_truth = [
  %{sample_id: 1, is_hallucination: true},
  %{sample_id: 2, is_hallucination: true},
  %{sample_id: 3, is_hallucination: true}
]

recall = MedicalMetrics.hallucination_recall(cvl_predictions, ground_truth)
#=> 0.667  # 2 out of 3 caught
```

**Note**: Both `:contradiction` and `:neutral` verdicts count as "caught" because neutral verdicts trigger human review.

#### Hallucination Precision

Measures what fraction of flagged items were actual hallucinations:

```elixir
cvl_predictions = [
  %{sample_id: 1, verdict: :contradiction},  # True positive
  %{sample_id: 2, verdict: :contradiction}   # False positive
]
ground_truth = [
  %{sample_id: 1, is_hallucination: true},
  %{sample_id: 2, is_hallucination: false}
]

precision = MedicalMetrics.hallucination_precision(cvl_predictions, ground_truth)
#=> 0.5  # 1 true positive out of 2 flagged
```

#### Hallucination F1

Harmonic mean of recall and precision:

```elixir
f1 = MedicalMetrics.hallucination_f1(cvl_predictions, ground_truth)
```

### Clinical Safety Score

Composite metric for overall clinical safety:

```elixir
predictions = [%{medications: [...], diagnoses: [...]}]
samples = [%{medications: [...], diagnoses: [...], sample_id: 1, is_hallucination: true}]
cvl_results = [%{sample_id: 1, verdict: :contradiction}]

safety = MedicalMetrics.clinical_safety_score(predictions, samples, cvl_results)
#=> 0.87
```

The score is weighted:
- **Medication accuracy (40%)**: Most safety-critical
- **Diagnosis accuracy (30%)**: Important for treatment decisions
- **Hallucination detection (30%)**: Prevents misinformation

### Statistical Comparison

Compare two models on the same dataset using McNemar's test:

```elixir
pred_a = ["A", "B", "A", "A", "B"]
pred_b = ["A", "A", "A", "B", "B"]
samples = [
  %{answer: "A"},
  %{answer: "B"},
  %{answer: "A"},
  %{answer: "A"},
  %{answer: "B"}
]

result = MedicalMetrics.mcnemar_test(pred_a, pred_b, samples)
#=> %{chi2: 4.5, p_value: 0.034, significant: true}
```

McNemar's test determines if the difference in error rates is statistically significant.

### Bootstrap Confidence Intervals

For arbitrary statistics:

```elixir
data = [0.72, 0.75, 0.71, 0.73, 0.74]
mean_fn = fn d -> Enum.sum(d) / length(d) end

{low, high} = MedicalMetrics.bootstrap_ci(data, mean_fn, iterations: 10_000)
#=> {0.718, 0.748}
```

## Report Generation

Generate a formatted report with confidence intervals:

```elixir
predictions = ["A", "A", "B", "B"]
samples = [
  %{answer: "A"},
  %{answer: "A"},
  %{answer: "A"},
  %{answer: "B"}
]

report = MedicalMetrics.format_report(predictions, samples)
#=> %{
#     accuracy: 0.75,
#     accuracy_ci_95: {0.3249, 0.9632},
#     sample_count: 4,
#     correct_count: 3
#   }

# Include medical metrics
report = MedicalMetrics.format_report(predictions, samples, medical_metrics: true)
#=> %{
#     accuracy: 0.75,
#     accuracy_ci_95: {0.3249, 0.9632},
#     sample_count: 4,
#     correct_count: 3,
#     medication_accuracy: 0.0,
#     diagnosis_accuracy: 0.0
#   }
```

## Target Benchmarks

| Metric | Target |
|--------|--------|
| Accuracy | Baseline +/-5% |
| Wilson CI | 95% for all reports |
| Hallucination Recall | >95% |
| Hallucination Precision | >85% |
| Clinical Safety Score | >85% |

## Using with crucible_harness

MedlumLlm metrics integrate with crucible_harness for experiment orchestration:

```elixir
defmodule MyExperiment do
  use CrucibleHarness.Experiment

  alias MedlumLlm.Eval.MedicalMetrics

  name "MedQA Zero-Shot"

  dataset :medqa
  dataset_config %{split: "test"}

  conditions [
    %{
      name: "biomistral_7b",
      fn: &evaluate_sample(&1, model: :biomistral_7b)
    },
    %{
      name: "openbio_8b",
      fn: &evaluate_sample(&1, model: :openbio_8b)
    }
  ]

  metrics [:accuracy, :latency_ms]

  defp evaluate_sample(sample, opts) do
    # Run inference and return metrics
    %{accuracy: ..., latency_ms: ...}
  end
end

# Run experiment
{:ok, report} = CrucibleHarness.run(MyExperiment)
```

## Fallback Behavior

When NSAI libraries (eval_ex, crucible_bench) are not available, MedicalMetrics uses built-in fallback implementations:

- `accuracy/2` - Simple correct/total calculation
- `wilson_ci/3` - Standard Wilson score formula
- `mcnemar_test/3` - Chi-square with Yates' correction
- `f1/3` - Token-level F1

This ensures MedlumLlm works standalone while gaining enhanced functionality with the full NSAI stack.

## See Also

- [MedlumLlm.Datasets](datasets.md) - Loading medical benchmarks
- [CVL Training Pipeline](cvl_training_pipeline.md) - Training hallucination detectors
- [ADR-004: Medical Metrics](/docs/adrs/ADR-004-medical-metrics.md) - Design decisions
