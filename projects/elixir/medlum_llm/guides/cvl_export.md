# CVL Export Guide

This guide covers exporting CVL labeled data for model training with quality filtering, clinical PII redaction, and reproducibility verification.

## Overview

The CVL export pipeline produces JSONL training data from human-labeled NLI samples with:

- **Quality Filtering** - Agreement thresholds, minimum labels
- **Clinical Redaction** - HIPAA-compliant PII removal
- **Reproducibility** - SHA256 manifests and deterministic ordering

## Quick Start

```elixir
# Basic export with defaults
{:ok, result} = MedlumLlm.CVL.ExportPipeline.export_training_data()

# Export with custom options
{:ok, result} = MedlumLlm.CVL.ExportPipeline.export_training_data(
  output_path: "priv/training/cvl_train_v1.jsonl",
  min_agreement: 0.85,
  min_labels: 3,
  redaction_mode: :aggressive
)
```

## Export Options

### Quality Thresholds

| Option | Default | Description |
|--------|---------|-------------|
| `min_agreement` | 0.80 | Minimum agreement score (0.0-1.0) |
| `min_labels` | 3 | Minimum labels per sample |
| `consensus_required` | true | Require majority verdict |

### Redaction Modes

| Mode | Description |
|------|-------------|
| `:standard` | High-confidence clinical identifiers |
| `:aggressive` | Standard + names, facilities, addresses |
| `:none` | No redaction (internal use only) |

### Output Settings

| Option | Default | Description |
|--------|---------|-------------|
| `output_path` | Auto-generated | JSONL output file path |
| `schema_version` | "1.1" | Schema version for validation |
| `include_metadata` | true | Include sample metadata |

## Export Format

### JSONL Structure

Each line is a JSON object:

```json
{
  "sample_id": "cvl_a1b2c3d4e5f6g7h8",
  "premise": "Patient has Type 2 diabetes with A1C of 9.2%...",
  "hypothesis": "Patient's diabetes is well controlled",
  "labels": [
    {
      "labeler_id": "a1b2c3d4e5f6",
      "verdict": "CONTRADICTION",
      "confidence": 5,
      "evidence_quality": "clear"
    },
    {
      "labeler_id": "d4e5f6g7h8i9",
      "verdict": "CONTRADICTION",
      "confidence": 4,
      "evidence_quality": "clear"
    },
    {
      "labeler_id": "g7h8i9j0k1l2",
      "verdict": "CONTRADICTION",
      "confidence": 5,
      "evidence_quality": "partial"
    }
  ],
  "consensus_verdict": "CONTRADICTION",
  "consensus_agreement": 1.0,
  "label_count": 3,
  "metadata": {
    "created_at": "2026-01-25T14:30:00Z",
    "labeling_time_avg": 45
  }
}
```

### Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `sample_id` | string | Unique sample identifier |
| `premise` | string | Source document (redacted) |
| `hypothesis` | string | Claim to verify (redacted) |
| `labels` | array | Individual labeler annotations |
| `consensus_verdict` | string | Majority verdict |
| `consensus_agreement` | float | Agreement percentage |
| `label_count` | integer | Number of labels |
| `metadata` | object | Additional metadata |

### Label Structure

| Field | Type | Description |
|-------|------|-------------|
| `labeler_id` | string | Hashed labeler identifier |
| `verdict` | string | NLI classification |
| `confidence` | integer | 1-5 confidence rating |
| `evidence_quality` | string | Evidence assessment |

## Clinical PII Redaction

### Standard Mode

Redacts high-confidence identifiers:

- Medical Record Numbers (MRN)
- Date of Birth (DOB)
- National Provider Identifier (NPI)
- DEA Numbers
- Medicare/Medicaid IDs
- Insurance IDs
- Medical dates
- Room/Bed numbers

```elixir
export_training_data(redaction_mode: :standard)
```

### Aggressive Mode

Standard patterns plus context-dependent entities:

- Provider names (Dr., MD, DO, NP, etc.)
- Facility names (Hospital, Medical Center, etc.)
- Street addresses

```elixir
export_training_data(redaction_mode: :aggressive)
```

### Redaction Examples

| Original | Standard | Aggressive |
|----------|----------|------------|
| `MRN: 12345678` | `[MRN_REDACTED]` | `[MRN_REDACTED]` |
| `DOB: 01/15/1980` | `[DOB_REDACTED]` | `[DOB_REDACTED]` |
| `Dr. Smith` | `Dr. Smith` | `[PROVIDER_REDACTED]` |
| `Mercy Hospital` | `Mercy Hospital` | `[FACILITY_REDACTED]` |

## Quality Filtering

### Agreement Calculation

Agreement is computed as the percentage of labels matching the majority verdict:

```
agreement = max_count / total_labels
```

Example with 3 labels:
- All same: 3/3 = 1.0
- Two same: 2/3 = 0.67
- All different: 1/3 = 0.33

### Filtering Pipeline

1. **Min Labels** - Exclude samples with fewer than `min_labels` annotations
2. **Agreement** - Exclude samples below `min_agreement` threshold
3. **Consensus** - Optionally require clear majority verdict

### Quality Metrics

```elixir
metrics = MedlumLlm.CVL.ExportPipeline.quality_metrics()

# Returns:
%{
  total_samples: 100,         # All samples with any labels
  complete_samples: 95,        # Samples with min_labels
  high_agreement_samples: 80,  # Above agreement threshold
  overall_agreement: 0.85,     # Average agreement score
  verdict_distribution: %{
    "ENTAILMENT" => 40,
    "CONTRADICTION" => 25,
    "NEUTRAL" => 30
  },
  labels_per_sample_avg: 3.1
}
```

## Manifest & Reproducibility

### Manifest Structure

Each export generates a manifest file (`*.manifest.json`):

```json
{
  "version": "1.0",
  "output_path": "priv/cvl_training/cvl_train_1706187600.jsonl",
  "row_count": 150,
  "sha256_hash": "a1b2c3d4...",
  "exported_at": "2026-01-25T14:00:00Z",
  "parameters": {
    "min_agreement": 0.80,
    "min_labels": 3,
    "redaction_mode": "aggressive",
    "schema_version": "1.1"
  }
}
```

### Verification

```elixir
# Verify export hasn't been modified
{:ok, :reproducible} = MedlumLlm.CVL.ExportPipeline.verify_export(
  "priv/cvl_training/cvl_train_1706187600.jsonl.manifest.json"
)
```

### Deterministic Ordering

Exports are ordered by `sample_id` for reproducibility:

```elixir
# Same parameters always produce identical output
{:ok, result1} = export_training_data(min_agreement: 0.80)
{:ok, result2} = export_training_data(min_agreement: 0.80)

result1.sha256_hash == result2.sha256_hash  # true (assuming no new labels)
```

## Consensus Export

Export with pre-computed consensus verdicts:

```elixir
{:ok, result} = MedlumLlm.CVL.ExportPipeline.export_with_consensus(
  min_agreement: 0.80,
  min_labels: 3
)
```

This ensures all exported samples have:
- Valid `consensus_verdict`
- `consensus_agreement` >= threshold
- At least `min_labels` annotations

## Export Workflows

### Training Data Export

```elixir
# Production export for model training
{:ok, result} = MedlumLlm.CVL.ExportPipeline.export_training_data(
  output_path: "data/cvl_train_#{Date.utc_today()}.jsonl",
  min_agreement: 0.85,
  min_labels: 3,
  redaction_mode: :aggressive,
  schema_version: "1.1"
)

IO.puts("Exported #{result.row_count} training samples")
IO.puts("Manifest: #{result.manifest_path}")
```

### Validation Data Export

```elixir
# Higher agreement for validation set
{:ok, result} = MedlumLlm.CVL.ExportPipeline.export_training_data(
  output_path: "data/cvl_validation.jsonl",
  min_agreement: 0.95,  # Higher threshold
  min_labels: 5         # More labels
)
```

### Analysis Export

```elixir
# Include all samples for analysis (no filtering)
{:ok, result} = MedlumLlm.CVL.ExportPipeline.export_training_data(
  output_path: "analysis/cvl_all_labels.jsonl",
  min_agreement: 0.0,   # No agreement filter
  min_labels: 1,        # Include partial labels
  consensus_required: false
)
```

## Integration with Training

### Loading Export in Python

```python
import json

def load_cvl_training_data(path):
    samples = []
    with open(path, 'r') as f:
        for line in f:
            sample = json.loads(line)
            samples.append({
                'premise': sample['premise'],
                'hypothesis': sample['hypothesis'],
                'label': sample['consensus_verdict'],
                'agreement': sample['consensus_agreement']
            })
    return samples
```

### HuggingFace Dataset

```python
from datasets import Dataset

def to_hf_dataset(path):
    samples = load_cvl_training_data(path)
    return Dataset.from_list(samples)
```

## Troubleshooting

### No Samples Exported

**Cause**: All samples filtered out by quality thresholds

**Solution**:
1. Check quality metrics: `ExportPipeline.quality_metrics()`
2. Lower thresholds temporarily to verify data exists
3. Request additional labels for incomplete samples

### Hash Mismatch on Verification

**Cause**: Export file was modified after generation

**Solution**:
1. Re-export from queue with same parameters
2. Check file for manual edits
3. Verify no concurrent writes occurred

### PII Not Redacted

**Cause**: Using `:none` redaction mode

**Solution**:
1. Use `:standard` or `:aggressive` mode
2. Add custom patterns if needed
3. Review MedlumLlm.PII.Clinical patterns

### Export Too Large

**Cause**: Many samples with sufficient labels

**Solution**:
1. Increase `min_agreement` threshold
2. Add filtering by date range
3. Export in batches by sample ID prefix
