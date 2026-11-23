# CVL Evaluation Metrics

MedlumLlm provides specialized evaluation metrics for the Clinical Verification Layer (CVL), its multi-agent hallucination detection system.

## Overview

Medical AI systems can produce hallucinations - factually incorrect statements that could lead to patient harm. CVL uses a multi-agent architecture to detect these hallucinations through Natural Language Inference (NLI).

### CVL Architecture

CVL uses 5 specialized verification agents:

1. **Medication Agent** (RxNorm) - Validates drug names, doses, frequencies
2. **Lab Agent** (LOINC) - Validates lab values and reference ranges
3. **Ontology Agent** - Checks SNOMED-CT/ICD-10 consistency
4. **Temporal Agent** - Validates timeline and progression logic
5. **Differential Diagnosis Agent** - Validates symptom-diagnosis relationships

### Verdict Classification

CVL classifies each claim using 3-way NLI:

| Verdict | Meaning | Flagged? |
|---------|---------|----------|
| **ENTAILMENT** | Claim is supported by evidence | No |
| **CONTRADICTION** | Claim conflicts with evidence | Yes |
| **NEUTRAL** | Claim cannot be verified | Yes |

**Important**: Both CONTRADICTION and NEUTRAL are flagged as potential hallucinations because ungrounded claims (NEUTRAL) are dangerous in medical contexts.

## Target Metrics

CVL evaluation has specific performance targets:

| Metric | Target | Rationale |
|--------|--------|-----------|
| Hallucination Recall | >95% | Safety-critical: don't miss real hallucinations |
| Hallucination Precision | >85% | Usability: minimize alert fatigue |
| Agent Agreement | >80% | Confidence: consistent classifications |

## Hallucination Detection Metrics

### Hallucination Recall

Recall measures how many actual hallucinations were caught:

```elixir
predictions = [
  %{sample_id: 1, verdict: :contradiction},
  %{sample_id: 2, verdict: :neutral},
  %{sample_id: 3, verdict: :entailment}
]

ground_truth = [
  %{sample_id: 1, is_hallucination: true},
  %{sample_id: 2, is_hallucination: true},
  %{sample_id: 3, is_hallucination: false}
]

recall = MedlumLlm.Eval.CvlMetrics.hallucination_recall(predictions, ground_truth)
# => 1.0 (both hallucinations caught)
```

**Formula**: `Caught Hallucinations / Total Actual Hallucinations`

**Edge Cases**:
- Returns 1.0 when no hallucinations exist (nothing to miss)

### Hallucination Precision

Precision measures how many flags were actual hallucinations:

```elixir
predictions = [
  %{sample_id: 1, verdict: :contradiction},  # Flag
  %{sample_id: 2, verdict: :neutral},        # Flag
  %{sample_id: 3, verdict: :entailment}      # Not flagged
]

ground_truth = [
  %{sample_id: 1, is_hallucination: true},   # True positive
  %{sample_id: 2, is_hallucination: false},  # False positive
  %{sample_id: 3, is_hallucination: false}
]

precision = MedlumLlm.Eval.CvlMetrics.hallucination_precision(predictions, ground_truth)
# => 0.5 (1 true flag out of 2 total flags)
```

**Formula**: `True Flags / Total Flags`

**Edge Cases**:
- Returns 1.0 when nothing is flagged (no false positives possible)

### Hallucination F1

F1 balances recall and precision:

```elixir
f1 = MedlumLlm.Eval.CvlMetrics.hallucination_f1(predictions, ground_truth)
# => 0.667 (harmonic mean of 1.0 recall and 0.5 precision)
```

**Formula**: `2 * (Precision * Recall) / (Precision + Recall)`

### Confusion Matrix

For detailed error analysis:

```elixir
matrix = MedlumLlm.Eval.CvlMetrics.hallucination_confusion_matrix(predictions, ground_truth)
# => %{
#      true_positive: 1,   # Flagged and actually hallucination
#      false_positive: 1,  # Flagged but not hallucination
#      true_negative: 1,   # Not flagged and not hallucination
#      false_negative: 0   # Not flagged but actually hallucination
#    }
```

## Calibration Error (ECE)

Expected Calibration Error measures how well confidence scores match actual accuracy:

```elixir
predictions = [
  %{verdict: :entailment, confidence: 0.9},
  %{verdict: :entailment, confidence: 0.9},
  %{verdict: :contradiction, confidence: 0.9}
]

samples = [
  %{label: :entailment},
  %{label: :entailment},
  %{label: :entailment}  # 2 correct, 1 incorrect at 90% confidence
]

ece = MedlumLlm.Eval.CvlMetrics.calibration_error(predictions, samples)
# => ~0.23 (actual accuracy 67% vs 90% confidence)
```

**Interpretation**:
- 0.0 = Perfectly calibrated (confidence matches accuracy)
- 1.0 = Completely miscalibrated

**Options**:
- `:bins` - Number of confidence bins (default: 10)

```elixir
MedlumLlm.Eval.CvlMetrics.calibration_error(predictions, samples, bins: 5)
```

## Multi-Agent Metrics

CVL's 5-agent architecture enables ensemble analysis.

### Agent Agreement Rate

Measures how often agents agree:

```elixir
agent_predictions = %{
  1 => %{med: :entailment, lab: :entailment, ont: :entailment},    # 100% agree
  2 => %{med: :contradiction, lab: :contradiction, ont: :neutral}  # 67% agree
}

agreement = MedlumLlm.Eval.CvlMetrics.agent_agreement_rate(agent_predictions)
# => 0.833 (average of 1.0 and 0.667)
```

**Formula**: Average of `(max_verdict_count / num_agents)` per sample

### Consensus Accuracy

Measures accuracy using majority vote:

```elixir
agent_predictions = %{
  1 => %{med: :entailment, lab: :entailment, ont: :contradiction},
  2 => %{med: :contradiction, lab: :contradiction, ont: :entailment}
}

ground_truth = [
  %{sample_id: 1, label: :entailment},    # Consensus correct
  %{sample_id: 2, label: :entailment}     # Consensus incorrect
]

accuracy = MedlumLlm.Eval.CvlMetrics.consensus_accuracy(agent_predictions, ground_truth)
# => 0.5
```

### Per-Agent Accuracy

Identifies strong and weak agents:

```elixir
agent_predictions = %{
  1 => %{med: :entailment, lab: :entailment},
  2 => %{med: :contradiction, lab: :entailment}
}

ground_truth = [
  %{sample_id: 1, label: :entailment},
  %{sample_id: 2, label: :contradiction}
]

per_agent = MedlumLlm.Eval.CvlMetrics.per_agent_accuracy(agent_predictions, ground_truth)
# => %{med: 1.0, lab: 0.5}
```

### Disagreement Analysis

Analyzes performance when agents disagree:

```elixir
analysis = MedlumLlm.Eval.CvlMetrics.disagreement_analysis(agent_predictions, ground_truth)
# => %{
#      disagreement_count: 1,
#      per_agent_accuracy: %{med: 1.0, lab: 0.0},
#      consensus_accuracy: 0.0
#    }
```

This helps identify:
- Which agents perform best in ambiguous cases
- Whether consensus helps or hurts accuracy

## Complete Evaluation Example

Here's a complete CVL evaluation workflow:

```elixir
defmodule CVLEvaluation do
  alias MedlumLlm.Eval.CvlMetrics

  def evaluate(predictions, ground_truth, agent_predictions) do
    # Hallucination detection metrics
    recall = CvlMetrics.hallucination_recall(predictions, ground_truth)
    precision = CvlMetrics.hallucination_precision(predictions, ground_truth)
    f1 = CvlMetrics.hallucination_f1(predictions, ground_truth)

    # Confusion matrix
    cm = CvlMetrics.hallucination_confusion_matrix(predictions, ground_truth)

    # Multi-agent metrics
    agreement = CvlMetrics.agent_agreement_rate(agent_predictions)
    consensus_acc = CvlMetrics.consensus_accuracy(agent_predictions, ground_truth)
    per_agent = CvlMetrics.per_agent_accuracy(agent_predictions, ground_truth)

    # Disagreement analysis
    disagreement = CvlMetrics.disagreement_analysis(agent_predictions, ground_truth)

    %{
      hallucination: %{
        recall: recall,
        precision: precision,
        f1: f1,
        confusion_matrix: cm
      },
      multi_agent: %{
        agreement_rate: agreement,
        consensus_accuracy: consensus_acc,
        per_agent_accuracy: per_agent,
        disagreement_analysis: disagreement
      },
      targets_met: %{
        recall_target: recall >= 0.95,
        precision_target: precision >= 0.85,
        agreement_target: agreement >= 0.80
      }
    }
  end
end
```

## Helper Functions

### Check if Verdict is Flagged

```elixir
MedlumLlm.Eval.CvlMetrics.flagged?(:entailment)     # => false
MedlumLlm.Eval.CvlMetrics.flagged?(:contradiction)  # => true
MedlumLlm.Eval.CvlMetrics.flagged?(:neutral)        # => true
```

### Get Valid Verdicts

```elixir
MedlumLlm.Eval.CvlMetrics.valid_verdicts()
# => [:entailment, :contradiction, :neutral]

MedlumLlm.Eval.CvlMetrics.flagged_verdicts()
# => [:contradiction, :neutral]
```

## Best Practices

1. **Prioritize Recall Over Precision** - In medical contexts, missing a hallucination (false negative) is worse than a false alarm. Target >95% recall first.

2. **Monitor Agent Agreement** - Low agreement may indicate ambiguous cases or agent calibration issues.

3. **Use Per-Agent Analysis** - Identify underperforming agents for targeted improvements.

4. **Track Calibration** - Well-calibrated confidence scores help clinicians prioritize reviews.

5. **Analyze Disagreements** - Cases where agents disagree often represent edge cases that need attention.

## API Reference

| Function | Description |
|----------|-------------|
| `hallucination_recall/2` | Proportion of hallucinations caught (target >95%) |
| `hallucination_precision/2` | Proportion of flags that are true (target >85%) |
| `hallucination_f1/2` | Harmonic mean of precision and recall |
| `hallucination_confusion_matrix/2` | TP/FP/TN/FN breakdown |
| `calibration_error/3` | Expected Calibration Error (ECE) |
| `agent_agreement_rate/1` | Average agreement across agents |
| `consensus_accuracy/2` | Majority vote accuracy |
| `per_agent_accuracy/2` | Individual agent accuracies |
| `disagreement_analysis/2` | Analysis when agents disagree |
| `flagged?/1` | Check if verdict is flagged |
