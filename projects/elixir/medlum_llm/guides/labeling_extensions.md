# Labeling Extensions Guide

This guide covers the medical-specific labeling extensions in `MedlumLlm.Labeling.*` for Clinical Verification Layer (CVL) training data export and evaluation workflows.

## Overview

The labeling extensions provide:

- **Type definitions** for NLI classification and CVL multi-agent verdicts
- **Validation functions** for clinical documents and agent outputs
- **Pre-built schemas** for NLI, clinical verification, and agent labeling
- **Builder functions** for constructing samples and labels
- **Metric constants** for CVL evaluation

## Quick Start

```elixir
alias MedlumLlm.Labeling.{NLI, CVL, Schemas, SampleBuilder, LabelBuilder}

# Build an NLI training sample
sample = SampleBuilder.build_nli_sample(
  "Patient is on metformin 500mg BID.",
  "Patient takes metformin 1000mg daily.",
  tenant_id: "medlum",
  source_run_id: "eval_001"
)

# Get the labeling schema
schema = Schemas.nli_schema(tenant_id: "medlum")

# Create a human annotation label
label = LabelBuilder.build_nli_label(%{
  assignment_id: "assign_001",
  sample_id: sample.id,
  queue_id: "cvl_queue",
  tenant_id: "medlum",
  user_id: "annotator_alice",
  verdict: :contradiction,
  time_spent_ms: 45_000,
  confidence: 5,
  reasoning: "Dose mismatch: 500mg BID vs 1000mg daily"
})
```

## NLI Classification

The Clinical Verification Layer uses 3-way Natural Language Inference (NLI) to detect hallucinations:

| Verdict | String Label | CVL Interpretation |
|---------|--------------|-------------------|
| `:entailment` | `"ENTAILMENT"` | Claim is verified by source documents |
| `:contradiction` | `"CONTRADICTION"` | Hallucination detected |
| `:neutral` | `"NEUTRAL"` | Insufficient evidence |

### Type Conversions

```elixir
alias MedlumLlm.Labeling.NLI

# Atom to string
NLI.verdict_to_label(:entailment)     # => "ENTAILMENT"
NLI.verdict_to_label(:contradiction)  # => "CONTRADICTION"

# String to atom
NLI.label_to_verdict("CONTRADICTION") # => {:ok, :contradiction}
NLI.label_to_verdict("INVALID")       # => {:error, :invalid_label}
NLI.label_to_verdict!("ENTAILMENT")   # => :entailment (raises on invalid)

# Validation
NLI.valid_label?("NEUTRAL")           # => true
NLI.valid_verdict?(:contradiction)    # => true
```

## CVL Multi-Agent Verification

CVL uses 5 specialized verification agents:

| Agent Type | Purpose | Ontology |
|------------|---------|----------|
| `:medication` | Drug name, dose, frequency | RxNorm |
| `:lab` | Lab values, reference ranges | LOINC |
| `:ontology` | Clinical terminology | SNOMED-CT/ICD-10 |
| `:temporal` | Timeline, progression | - |
| `:differential` | Diagnosis-symptom mapping | - |

### Agent Verdicts

```elixir
alias MedlumLlm.Labeling.CVL

# Validate an agent verdict
verdict = %{
  verdict: :contradiction,
  confidence: 0.92,
  evidence: ["Dose mismatch: 500mg vs 1000mg"],
  ontology_codes: ["861004"]
}

{:ok, validated} = CVL.validate_agent_verdict(verdict)
# Or raise on invalid:
validated = CVL.validate_agent_verdict!(verdict)
```

### Consensus Results

```elixir
consensus = %{
  agent_verdicts: %{
    medication: validated_med_verdict,
    lab: validated_lab_verdict
  },
  consensus_verdict: :contradiction,
  consensus_method: :weighted_vote,
  dissent_count: 1
}

{:ok, validated_consensus} = CVL.validate_consensus_result(consensus)
```

## Clinical Documents

Clinical documents represent source materials for verification.

### Document Types

- `:discharge_summary` - Hospital discharge documentation
- `:lab_report` - Laboratory test results
- `:consultation` - Specialist consultation notes
- `:imaging` - Radiology reports
- `:medication_list` - Current medications
- `:progress_note` - Clinical progress notes

### Creating Documents

```elixir
alias MedlumLlm.Labeling.ClinicalDocument

doc = %{
  type: :discharge_summary,
  content: "Patient discharged on metformin 500mg BID...",
  date: ~D[2026-01-15],
  provider_type: "endocrinology",
  ontology_codes: %{
    snomed_ct: ["44054006"],
    icd10: ["E11.9"],
    rxnorm: ["861004"],
    loinc: []
  }
}

# Validate
{:ok, validated} = ClinicalDocument.validate(doc)

# Serialize for JSON
json_map = ClinicalDocument.serialize(validated)

# Deserialize from JSON
{:ok, parsed} = ClinicalDocument.deserialize(json_map)
```

## Pre-built Schemas

### NLI Schema

For human annotation of premise-hypothesis pairs:

```elixir
alias MedlumLlm.Labeling.Schemas

schema = Schemas.nli_schema(
  tenant_id: "medlum",
  namespace: "cvl"
)

# Fields included:
# - nli_label (select: ENTAILMENT, CONTRADICTION, NEUTRAL)
# - confidence (scale: 1-5)
# - evidence_spans (text)
# - reasoning (text)
# - difficulty (select: easy, medium, hard)
```

### Clinical Verification Schema

For comprehensive document verification:

```elixir
schema = Schemas.clinical_verification_schema()

# Fields included:
# - overall_verdict (select: VERIFIED, HALLUCINATION, PARTIAL, UNCERTAIN)
# - hallucinated_claims (text)
# - missing_critical_info (text)
# - medication_accuracy (scale: 0-100)
# - lab_accuracy (scale: 0-100)
# - temporal_accuracy (scale: 0-100)
```

### Agent Verification Schema

For automated CVL agent output:

```elixir
schema = Schemas.agent_verification_schema()

# Fields included:
# - verdict (select: ENTAILMENT, CONTRADICTION, NEUTRAL, ABSTAIN)
# - confidence (scale: 0-100)
# - evidence (text)
# - ontology_codes (text)
```

## Building Samples

### NLI Samples

```elixir
alias MedlumLlm.Labeling.SampleBuilder

sample = SampleBuilder.build_nli_sample(
  "Patient is on metformin 500mg BID.",        # premise
  "Patient takes metformin 1000mg daily.",     # hypothesis
  tenant_id: "medlum",
  namespace: "cvl",
  source_run_id: "eval_001",
  model: "openbio_8b",
  model_confidence: 0.85
)

# Generates ID: cvl_<random>
# Sets task_type: "nli"
# Includes lineage_ref when source_run_id provided
```

### Clinical Samples

```elixir
documents = [
  %{
    type: :discharge_summary,
    content: "Patient discharged on metformin 500mg BID...",
    date: ~D[2026-01-15],
    provider_type: "endocrinology",
    ontology_codes: %{
      snomed_ct: ["44054006"],
      icd10: ["E11.9"],
      rxnorm: ["861004"],
      loinc: []
    }
  },
  %{
    type: :lab_report,
    content: "HbA1c: 7.2%...",
    date: ~D[2026-01-14],
    provider_type: "laboratory",
    ontology_codes: %{snomed_ct: [], icd10: [], rxnorm: [], loinc: ["4548-4"]}
  }
]

sample = SampleBuilder.build_clinical_sample(
  documents,
  "Patient has well-controlled diabetes on metformin 1000mg daily.",
  claims: [%{"text" => "metformin 1000mg daily", "span" => [45, 67]}]
)

# Aggregates ontology codes into metadata
# Sets task_type: "clinical_verification"
```

### From Evaluation Failures

```elixir
failure = %{
  "question" => "What medication is the patient taking?",
  "predicted" => "metformin 1000mg",
  "correct" => "metformin 500mg BID",
  "task" => "mcq",
  "model" => "openbio_8b"
}

sample = SampleBuilder.build_from_eval_failure(
  failure,
  run_id: "eval_001"
)
```

## Building Labels

### Human NLI Labels

```elixir
alias MedlumLlm.Labeling.LabelBuilder

label = LabelBuilder.build_nli_label(%{
  assignment_id: "assign_001",
  sample_id: sample.id,
  queue_id: "cvl_nli_queue",
  tenant_id: "medlum",
  user_id: "annotator_alice",
  verdict: :contradiction,
  time_spent_ms: 45_000,
  confidence: 5,
  reasoning: "Dose mismatch",
  evidence_spans: "metformin 500mg BID",
  difficulty: "easy"
})
```

### Agent Labels

```elixir
agent_verdict = %{
  verdict: :contradiction,
  confidence: 0.92,
  evidence: ["Dose mismatch: 500mg vs 1000mg"],
  ontology_codes: ["861004"]
}

label = LabelBuilder.build_agent_label(
  :medication,
  agent_verdict,
  assignment_id: "assign_001",
  sample_id: sample.id,
  queue_id: "agent_queue",
  tenant_id: "medlum",
  agent_id: "medication_agent_v1",
  time_spent_ms: 150
)

# user_id is set to "agent:medication_agent_v1"
# metadata includes is_agent_label: true
```

### Consensus Labels

```elixir
consensus_result = %{
  agent_verdicts: %{
    medication: med_verdict,
    lab: lab_verdict
  },
  consensus_verdict: :contradiction,
  consensus_method: :weighted_vote,
  dissent_count: 1
}

label = LabelBuilder.build_consensus_label(
  consensus_result,
  assignment_id: "assign_001",
  sample_id: sample.id,
  queue_id: "consensus_queue",
  tenant_id: "medlum",
  time_spent_ms: 500
)

# user_id is "agent:cvl_consensus"
# Includes serialized agent verdicts in values
```

## Medical Metrics

Standard metric keys for CVL evaluation:

```elixir
alias MedlumLlm.Labeling.Metrics

# CVL-specific metrics
Metrics.cvl_metric_keys()
# [:cvl_accuracy, :hallucination_precision, :hallucination_recall,
#  :hallucination_f1, :medication_accuracy, :diagnosis_accuracy,
#  :lab_accuracy, :temporal_accuracy]

# Statistical metrics
Metrics.statistical_keys()
# [:confidence_interval_lower, :confidence_interval_upper, :sample_size,
#  :p_value, :standard_error, :cohens_kappa, :fleiss_kappa]

# Validation
Metrics.valid_cvl_metric?(:hallucination_f1)  # => true
Metrics.valid_metric_key?(:accuracy)          # => true

# Templates for EvalRun.metrics
template = Metrics.cvl_metrics_template()
# %{"cvl_accuracy" => nil, "hallucination_precision" => nil, ...}
```

## JSON Serialization

All builder functions create structs that serialize cleanly to JSON:

```elixir
sample = SampleBuilder.build_nli_sample("premise", "hypothesis")
{:ok, json} = Jason.encode(sample)

# Parse and reconstruct
{:ok, data} = Jason.decode(json)
# Use data in downstream systems
```

## Integration with Forge/Anvil

Samples built with these extensions are compatible with the Forge pipeline system and Anvil labeling queues:

1. Build samples with `SampleBuilder`
2. Export to Forge for preprocessing
3. Create assignments in Anvil with `Schemas`
4. Collect labels structured per `LabelBuilder`
5. Track evaluation with standard metric keys

See the examples directory for complete workflow demonstrations.
