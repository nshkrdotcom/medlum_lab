# CVL Training Pipeline

This guide explains the Clinical Verification Layer (CVL) training data pipeline implemented using the Forge library.

## Overview

The CVL Training Pipeline generates NLI (Natural Language Inference) training data from evaluation failures. It processes evaluation results, extracts verifiable claims, runs multi-agent verification, and exports low-confidence samples for human labeling via Anvil.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          CVL Training Pipeline                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐    ┌────────────────────────────────────────────────────┐ │
│  │   SOURCE    │    │                    STAGES                          │ │
│  │             │    │                                                    │ │
│  │ Evaluation  │───▶│ Normalize ─▶ Extract ─▶ Generate ─▶ Redact ─▶ Export│ │
│  │  Failures   │    │   Text       Claims      NLI       PII      Anvil │ │
│  │             │    │                                                    │ │
│  └─────────────┘    └────────────────────────────────────────────────────┘ │
│                                        │                                    │
│                                        ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         MEASUREMENTS                                 │   │
│  │                                                                      │   │
│  │  ┌───────────┐  ┌───────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐│   │
│  │  │Medication │  │  Lab  │  │ Ontology │  │ Temporal │  │Differential│   │
│  │  │  Agent    │  │ Agent │  │  Agent   │  │  Agent   │  │  Agent   ││   │
│  │  └─────┬─────┘  └───┬───┘  └────┬─────┘  └────┬─────┘  └────┬─────┘│   │
│  │        │            │           │             │              │      │   │
│  │        └────────────┴───────────┴─────────────┴──────────────┘      │   │
│  │                                 │                                    │   │
│  │                                 ▼                                    │   │
│  │                        ┌────────────────┐                           │   │
│  │                        │ Agent Consensus│                           │   │
│  │                        └───────┬────────┘                           │   │
│  │                                │                                    │   │
│  │                                ▼                                    │   │
│  │                        ┌────────────────┐                           │   │
│  │                        │  Confidence    │                           │   │
│  │                        └────────────────┘                           │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                        │                                    │
│                                        ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    AUDITED POSTGRES STORAGE                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Running the Pipeline

```elixir
# Run with default configuration
{:ok, stats} = MedlumLlm.CVL.TrainingPipeline.run()

# Run with custom filters
{:ok, stats} = MedlumLlm.CVL.TrainingPipeline.run(
  filters: [:incorrect, :contradiction],
  confidence_threshold: 0.6
)

# Stream samples for processing
MedlumLlm.CVL.TrainingPipeline.stream()
|> Enum.take(100)
|> Enum.each(&process_sample/1)
```

### Configuration

Add to your `config/config.exs`:

```elixir
config :medlum_llm, MedlumLlm.CVL.TrainingPipeline,
  results_dir: "priv/eval_results",
  filters: [:error, :incorrect, :low_confidence],
  min_confidence: 0.5,
  confidence_threshold: 0.5,
  redaction_mode: :aggressive,
  anvil_queue: "cvl_verification"
```

## Pipeline Stages

### 1. EvaluationFailureSource

Reads evaluation results from JSON files in `priv/eval_results/`.

**Input**: JSON files with schema:
```json
{
  "run": {"id": "run_1", "benchmark": "medqa_zero_shot"},
  "errors": [
    {
      "sample_idx": 0,
      "error": "incorrect",
      "model": "openbio_8b",
      "context": "...",
      "model_output": "...",
      "expected": "A",
      "predicted": "B"
    }
  ]
}
```

**Output**: `Forge.Sample` structs with evaluation failure data.

### 2. NormalizeText

Cleans and normalizes text for consistent processing:
- Unicode NFC normalization
- Smart quote replacement
- Whitespace standardization
- Control character removal

### 3. ClaimExtraction

Splits text into verifiable claims:
- Sentence and bullet point splitting
- Claim categorization (medication, diagnosis, lab_value, procedure, temporal)
- Span tracking for evidence linking

**Example**:
```
Input: "Patient takes metformin 500mg daily. Blood pressure is 120/80."

Output: [
  %{text: "Patient takes metformin 500mg daily", type: :medication},
  %{text: "Blood pressure is 120/80", type: :lab_value}
]
```

### 4. NLIPairGenerator

Creates premise-hypothesis pairs for NLI training:

**Label Mapping**:
| Error Type | NLI Label |
|------------|-----------|
| `:incorrect` | `:contradiction` |
| `:contradiction` | `:contradiction` |
| `:error` | `:neutral` |
| `:low_confidence` | `:neutral` |

### 5. PIIRedaction

HIPAA-compliant redaction using `MedlumLlm.Guardrails.Redactor`:
- Redacts all 18 HIPAA identifiers
- Preserves medical terminology
- Generates audit manifests

### 6. AnvilExport

Exports low-confidence samples for human labeling:
- Filters by confidence threshold
- Formats for Anvil 3-way NLI task
- Tracks export status

## Measurements

### CVL Agents

Each agent verifies claims using specialized medical knowledge:

| Agent | Domain | Ontology |
|-------|--------|----------|
| `MedicationAgent` | Drug names, doses, frequencies | RxNorm |
| `LabAgent` | Lab values, reference ranges | LOINC |
| `OntologyAgent` | Diagnoses, conditions | SNOMED-CT, ICD-10 |
| `TemporalAgent` | Timeline consistency | - |
| `DifferentialAgent` | Symptom-diagnosis mapping | Clinical KB |

### AgentConsensus

Aggregates agent verdicts using weighted voting:

```elixir
# Agent weights
%{
  medication: 1.2,  # Medications often hallucinated
  lab: 1.1,
  ontology: 1.3,    # Diagnoses critical
  temporal: 0.9,
  differential: 1.0
}
```

**Veto Rule**: 2+ contradictions = overall contradiction

### Confidence

Computes calibrated confidence score:

```
confidence = 0.6 × agreement_score + 0.4 × strength_score
```

**Thresholds**:
- `≥ 0.85`: High confidence (auto-accept)
- `0.5-0.85`: Medium confidence (may need review)
- `< 0.5`: Low confidence (requires human review)

## Storage

### AuditedPostgres

Wraps `Forge.Storage.Postgres` with HIPAA-compliant audit logging:

- All operations logged via Telemetry
- Sample IDs are hashed (no PHI in logs)
- Pipeline versioning and manifests

```elixir
# Telemetry event
[:medlum_llm, :storage, :audit]

# Event metadata
%{
  timestamp: DateTime.utc_now(),
  operation: :put_sample,
  sample_id_hash: "a1b2c3d4...",
  pipeline_name: :cvl_training
}
```

## Exporting Training Data

### JSONL Export

```elixir
# Export labeled samples
{:ok, count} = MedlumLlm.CVL.TrainingPipeline.export_training_data(
  output_path: "training_data.jsonl",
  filters: [status: :labeled],
  include_measurements: true
)
```

### Output Format

```json
{
  "sample_id": "cvl_medqa_openbio_0",
  "premise": "Patient has type 2 diabetes...",
  "hypothesis": "Patient has type 1 diabetes.",
  "label": "contradiction",
  "claim_type": "diagnosis",
  "measurements": {
    "consensus_verdict": "contradiction",
    "confidence_score": 0.87,
    "agreement": 0.8
  }
}
```

## Human Labeling with Anvil

### Queue Configuration

The pipeline creates an Anvil queue for 3-way NLI classification:

- **Task type**: NLI classification
- **Options**: entailment, contradiction, neutral
- **Annotators per sample**: 3
- **Agreement threshold**: 67%

### Getting Samples for Review

```elixir
# Get all low-confidence samples
{:ok, samples} = MedlumLlm.CVL.TrainingPipeline.samples_for_review(
  confidence_threshold: 0.5
)

Enum.each(samples, fn sample ->
  IO.puts("Sample #{sample.id}: confidence #{sample.measurements.confidence.score}")
end)
```

## Testing

### Running Tests

```bash
# Run CVL tests only
mix test test/medlum_llm/cvl/

# Run with coverage
mix test --cover

# Run specific test file
mix test test/medlum_llm/cvl/stages/claim_extraction_test.exs
```

### Test Data

Create test evaluation results in `test/fixtures/eval_results/`:

```json
{
  "run": {"id": "test_run", "benchmark": "test"},
  "errors": [
    {
      "sample_idx": 0,
      "error": "incorrect",
      "model": "test_model",
      "context": "Patient takes metformin 500mg daily.",
      "model_output": "Patient takes metformin 1000mg daily.",
      "expected": "500mg",
      "predicted": "1000mg"
    }
  ]
}
```

## Troubleshooting

### Common Issues

**No samples processed**
- Check `results_dir` configuration
- Verify JSON files match expected schema
- Check filter settings

**PII not redacted**
- Ensure `llm_guard` dependency is available
- Check redaction mode setting
- Verify `MedlumLlm.Guardrails.Redactor` works

**Anvil export fails**
- Check Anvil bridge configuration
- Verify queue exists
- Check network connectivity

### Debugging

Enable debug logging:

```elixir
config :logger, :console,
  level: :debug

config :medlum_llm, :log_level, :debug
```

## See Also

- [CVL Measurements Guide](cvl_measurements.md)
- [HIPAA Compliance Guide](hipaa_compliance.md)
- [Redaction Guide](redaction.md)
