# CVL Training Data Guide

This guide covers versioned training data management for the Clinical Verification Layer (CVL) agents in MedlumLlm.

## Overview

The CVL system consists of 5 specialized agents that verify medical content:

| Agent | Purpose | Common Errors |
|-------|---------|---------------|
| `:medication` | Validates medication references | Drug names, doses, frequencies |
| `:lab` | Validates lab values | Reference ranges, units, interpretations |
| `:ontology` | Verifies medical codes | SNOMED-CT, ICD-10, RxNorm, LOINC |
| `:temporal` | Checks temporal consistency | Timelines, dates, sequences |
| `:differential` | Validates diagnosis reasoning | Differential diagnoses, reasoning chains |

Each agent requires training data in NLI (Natural Language Inference) format.

## Training Data Format

CVL training data follows the NLI format with medical extensions:

```elixir
%{
  id: "sample_001",
  premise: "The patient is on metformin 500mg twice daily.",
  hypothesis: "The patient takes metformin 1000mg once daily.",
  verdict: :contradiction,          # :entailment | :contradiction | :neutral
  evidence: [
    "Dose mismatch: 500mg vs 1000mg",
    "Frequency mismatch: twice daily vs once daily"
  ],
  ontology_codes: ["861004"],       # RxNorm code for metformin
  agent_type: :medication,
  confidence: 0.95
}
```

### Verdict Types

| Verdict | Description | Example |
|---------|-------------|---------|
| `:entailment` | Hypothesis follows from premise | "Patient takes metformin 500mg BID" |= "Patient is on diabetes medication" |
| `:contradiction` | Hypothesis contradicts premise | "Dose is 500mg" _|_ "Dose is 1000mg" |
| `:neutral` | No direct relationship | "Patient is on metformin" ~ "Patient may need insulin in future" |

## Creating Training Data

### Basic Creation

```elixir
alias MedlumLlm.Datasets.CVLTraining

# Define samples
positive_samples = [
  %{
    premise: "Patient prescribed metformin 500mg BID.",
    hypothesis: "Patient takes metformin twice daily.",
    evidence: ["Frequency matches: BID = twice daily"]
  }
]

negative_samples = [
  %{
    premise: "Patient prescribed metformin 500mg BID.",
    hypothesis: "Patient takes metformin 1000mg daily.",
    evidence: ["Dose mismatch", "Frequency mismatch"]
  }
]

# Create versioned training data
{:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
  positive_samples: positive_samples,
  negative_samples: negative_samples,
  ontology_sources: ["RxNorm_2026AA"]
)
```

### Options for `create/3`

| Option | Type | Description |
|--------|------|-------------|
| `:positive_samples` | List | Entailment samples |
| `:negative_samples` | List | Contradiction samples |
| `:neutral_samples` | List | Neutral samples (optional) |
| `:ontology_sources` | List | Ontology versions used |
| `:parent_version` | String | Previous version this derives from |
| `:eval_run_id` | String | Evaluation run that generated failures |

### Metadata Tracking

The created dataset includes comprehensive metadata:

```elixir
dataset.metadata
# => %{
#   domain: :medical,
#   clinical_area: "cvl_training",
#   task: :cvl,
#   agent_type: :medication,
#   version: "v1.0.0",
#   ontology_sources: ["RxNorm_2026AA"],
#   sample_counts: %{
#     entailment: 1,
#     contradiction: 1,
#     neutral: 0
#   },
#   created_at: ~U[2026-01-25 10:00:00Z]
# }
```

## Version Management

### Version Naming Convention

Training data versions follow the pattern:
```
cvl_{agent}_{version}_{hash_prefix}
```

Example: `cvl_medication_v1.0.0_a1b2c3`

### Loading Training Data

```elixir
# Load specific version
{:ok, dataset} = CVLTraining.load(:medication, "v1.0.0")

# Load latest version
{:ok, dataset} = CVLTraining.load_latest(:medication)

# List all versions
CVLTraining.list_versions(:medication)
# => ["v2.0.0", "v1.1.0", "v1.0.0"]

# Get version history
CVLTraining.lineage(:medication)
# => [%{version: "v2.0.0", ...}, %{version: "v1.0.0", ...}]
```

## Stratified Splitting

CVL training data should be split while maintaining verdict distribution:

```elixir
{:ok, dataset} = CVLTraining.load_latest(:medication)

# Stratified split by verdict
{train, test} = CVLTraining.split(dataset,
  ratio: 0.8,
  seed: 42
)

# Check distribution is maintained
train_verdicts = Enum.frequencies_by(train.data, & &1.verdict)
test_verdicts = Enum.frequencies_by(test.data, & &1.verdict)

# Both should have similar proportions of each verdict type
```

## Creating from Evaluation Failures

A common workflow is creating training data from evaluation failures:

```elixir
# Evaluation failures from MedlumLlm
failures = [
  %{
    id: "fail_001",
    question: "What medication is the patient on?",
    expected: "metformin 500mg BID",
    predicted: "metformin 1000mg daily",
    model_confidence: 0.7,
    error_type: :medication_error,
    error_message: "Dose and frequency mismatch"
  },
  %{
    id: "fail_002",
    question: "What is the lab value?",
    expected: "HbA1c 7.2%",
    predicted: "HbA1c 6.5%",
    error_type: :lab_error,
    error_message: "Value mismatch"
  }
]

# Create training data for medication agent
{:ok, dataset} = CVLTraining.from_eval_failures(:medication, failures, "v1.1.0",
  eval_run_id: "eval_001",
  model: "openbio_8b"
)

# Only medication_error failures are included
length(dataset.data)  # => 1
```

### Failure Filtering by Agent

Failures are automatically filtered by error type:

| Agent | Matched Error Types |
|-------|---------------------|
| `:medication` | `:medication_error`, `:drug_error`, `:dose_error` |
| `:lab` | `:lab_error`, `:lab_value_error`, `:reference_range_error` |
| `:ontology` | `:ontology_error`, `:code_error`, `:terminology_error` |
| `:temporal` | `:temporal_error`, `:timeline_error`, `:date_error` |
| `:differential` | `:differential_error`, `:diagnosis_error`, `:reasoning_error` |

### Custom Transform Functions

```elixir
custom_transform = fn failure, agent ->
  %{
    id: failure.id,
    premise: failure.expected,
    hypothesis: failure.predicted,
    verdict: :contradiction,
    evidence: [failure.error_message],
    ontology_codes: [],
    agent_type: agent,
    confidence: 1.0 - failure.model_confidence,
    source: %{
      eval_run_id: failure.eval_run_id,
      question: failure.question
    }
  }
end

{:ok, dataset} = CVLTraining.from_eval_failures(:medication, failures, "v1.1.0",
  transform_fn: custom_transform
)
```

## Lineage Tracking

### Creating Artifact References

```elixir
{:ok, dataset} = CVLTraining.load_latest(:medication)

# Get artifact reference
ref = CVLTraining.artifact_ref(dataset)
# => %LineageIR.ArtifactRef{
#   artifact_id: "...",
#   type: "cvl_training_data",
#   uri: "datasets_ex://cvl_medication_v1.0.0_..."
# }
```

### Building Lineage Graphs

```elixir
# Evaluation run artifact
eval_ref = %LineageIR.ArtifactRef{
  artifact_id: "eval_001",
  type: "eval_run",
  metadata: %{model: "openbio_8b", dataset: "medqa"}
}

# Create training data from failures
{:ok, training} = CVLTraining.from_eval_failures(:medication, failures, "v1.1.0")
training_ref = CVLTraining.artifact_ref(training)

# Create lineage edge
edge = CVLTraining.lineage_edge(eval_ref, training_ref,
  relationship: "exported_from",
  metadata: %{
    agent: :medication,
    failure_count: length(failures)
  }
)
```

### Lineage Pattern: Evaluation to Training

```
Evaluation Run (MedQA v1.0.0, model: openbio_8b)
    |
    | exported_from
    v
Failure Export (failures_001)
    |
    | derived_from
    v
    +-> CVL Medication v1.0.0
    |       |
    |       | trained_on
    |       v
    |   Medication Agent v2.0.0
    |
    +-> CVL Lab v1.0.0 -> Lab Agent v2.0.0
    |
    +-> CVL Ontology v1.0.0 -> Ontology Agent v2.0.0
```

## Sample Validation

Validate individual samples before creating datasets:

```elixir
sample = %{
  premise: "Patient is on aspirin.",
  hypothesis: "Patient takes aspirin daily.",
  verdict: :entailment
}

{:ok, validated} = CVLTraining.validate_sample(sample)
# => {:ok, %{premise: ..., hypothesis: ..., verdict: :entailment}}

# Invalid sample
bad_sample = %{premise: "Only premise"}
{:error, errors} = CVLTraining.validate_sample(bad_sample)
# => {:error, ["Missing required fields: [:hypothesis, :verdict]"]}
```

## Quality Checks

Use the validators module for comprehensive checks:

```elixir
alias MedlumLlm.Datasets.Validators

{:ok, dataset} = CVLTraining.load_latest(:medication)

# Format validation
{:ok, report} = Validators.validate_cvl(dataset)
# => %{valid: true, total_items: 100, ...}

# With evidence requirement
{:ok, report} = Validators.validate_cvl(dataset, require_evidence: true)

# Full quality check
{:ok, report} = Validators.full_quality_check(dataset, :cvl)
# => %{
#   format_validation: %{valid: true, ...},
#   duplicates: %{duplicate_rate: 0.01, ...},
#   distribution: %{...},
#   profile: %{...}
# }
```

## Best Practices

### 1. Include Diverse Evidence

```elixir
negative_sample = %{
  premise: "Metformin 500mg twice daily",
  hypothesis: "Metformin 1000mg once daily",
  evidence: [
    "Dose mismatch: 500mg vs 1000mg",
    "Frequency mismatch: BID vs daily",
    "Total daily dose differs: 1000mg vs 1000mg (same, but regimen differs)"
  ]
}
```

### 2. Track Ontology Versions

```elixir
{:ok, dataset} = CVLTraining.create(:medication, "v1.0.0",
  positive_samples: samples,
  ontology_sources: [
    "RxNorm_2026AA",
    "SNOMED_CT_US_2026_01_01"
  ]
)
```

### 3. Use Iterative Improvement

```elixir
# Initial training data
{:ok, v1} = CVLTraining.create(:medication, "v1.0.0", initial_samples)

# After evaluation, create improved version
{:ok, v2} = CVLTraining.from_eval_failures(:medication, new_failures, "v2.0.0",
  parent_version: "v1.0.0"
)
```

### 4. Maintain Balanced Verdicts

```elixir
# Aim for roughly equal distribution
sample_counts = %{
  entailment: 100,
  contradiction: 100,
  neutral: 50  # Neutral often less common
}
```

### 5. Version with Meaningful Tags

```elixir
# Use semantic versioning
"v1.0.0"  # Initial release
"v1.1.0"  # Added hard negatives
"v2.0.0"  # Major ontology update
```

## Complete Workflow Example

```elixir
alias MedlumLlm.Datasets.{CVLTraining, Validators}

# 1. Create initial training data
positives = load_entailment_samples()
negatives = load_contradiction_samples()

{:ok, v1} = CVLTraining.create(:medication, "v1.0.0",
  positive_samples: positives,
  negative_samples: negatives,
  ontology_sources: ["RxNorm_2026AA"]
)

# 2. Validate
{:ok, report} = Validators.validate_cvl(v1)
IO.inspect(report)

# 3. Split for training
{train, test} = CVLTraining.split(v1, ratio: 0.8, seed: 42)

# 4. Train agent (external step)
# agent = train_medication_agent(train.data)

# 5. Evaluate and collect failures
# failures = evaluate_agent(agent, test.data)

# 6. Create improved version
failures = [
  %{error_type: :medication_error, expected: "...", predicted: "..."}
]

{:ok, v2} = CVLTraining.from_eval_failures(:medication, failures, "v2.0.0",
  parent_version: "v1.0.0"
)

# 7. Track lineage
v1_ref = CVLTraining.artifact_ref(v1)
v2_ref = CVLTraining.artifact_ref(v2)

edge = CVLTraining.lineage_edge(v1_ref, v2_ref,
  relationship: "improved_from",
  metadata: %{failure_count: length(failures)}
)

# 8. List version history
CVLTraining.list_versions(:medication)
# => ["v2.0.0", "v1.0.0"]
```

## See Also

- [Medical Datasets Guide](medical_datasets.md) - Loading medical datasets
- [MedlumLlm README](../README.md) - Main library documentation
- [Lineage IR Documentation](https://hexdocs.pm/lineage_ir) - Artifact and provenance types
