# CVL Labeling Guide

This guide covers the human labeling workflow for CVL (Clinical Verification Layer) training data collection using the Anvil labeling platform.

## Overview

CVL uses Natural Language Inference (NLI) to detect hallucinations in AI-generated medical summaries. Human labelers classify premise/hypothesis pairs as ENTAILMENT, CONTRADICTION, or NEUTRAL to create high-quality training data.

### Key Components

- **LabelingSchema** - Defines the schema for NLI classification labels
- **LabelingQueue** - Manages the Anvil queue with redundancy policy
- **SampleLoader** - Loads evaluation failures from Forge
- **ExportPipeline** - Exports labeled data with quality filtering
- **ForgeBridge** - Bidirectional sync between Forge and Anvil

## Quick Start

### 1. Create the Labeling Queue

```elixir
# Create queue with default settings (3 labels per sample)
{:ok, _} = MedlumLlm.CVL.LabelingQueue.create_queue()

# Or customize
{:ok, _} = MedlumLlm.CVL.LabelingQueue.create_queue(
  labels_per_sample: 5,
  assignment_timeout: 7200
)
```

### 2. Register Labelers

```elixir
# Register human labelers
:ok = MedlumLlm.CVL.LabelingQueue.register_labelers([
  "labeler_alice",
  "labeler_bob",
  "labeler_carol"
])

# Register reviewers with elevated permissions
:ok = MedlumLlm.CVL.LabelingQueue.register_labelers(["reviewer_dave"], :reviewer)
```

### 3. Load Samples from Evaluation Runs

```elixir
# Load samples from a specific evaluation run
{:ok, count} = MedlumLlm.CVL.SampleLoader.load_from_eval_run("eval_20260125_1234")

# Load with filters
{:ok, count} = MedlumLlm.CVL.SampleLoader.load_from_eval_run(
  "eval_20260125_1234",
  error_types: [:contradiction, :incorrect],
  max_samples: 100
)
```

### 4. Labelers Complete Assignments

```elixir
# Get next assignment for a labeler
{:ok, assignment} = MedlumLlm.CVL.LabelingQueue.get_next_assignment("labeler_alice")

# Submit label
{:ok, label} = MedlumLlm.CVL.LabelingQueue.submit_label(
  assignment.id,
  %{
    "verdict" => "ENTAILMENT",
    "confidence" => 4,
    "evidence_quality" => "clear",
    "reasoning" => "The premise explicitly states the diagnosis"
  }
)
```

### 5. Export Training Data

```elixir
# Export with quality filtering
{:ok, result} = MedlumLlm.CVL.ExportPipeline.export_training_data(
  min_agreement: 0.80,
  min_labels: 3,
  redaction_mode: :aggressive
)

# Check export results
IO.puts("Exported #{result.row_count} samples to #{result.output_path}")
IO.puts("SHA256: #{result.sha256_hash}")
```

## Schema Definition

The CVL NLI labeling schema defines four fields:

### verdict (required)

Select the NLI relationship:

- **ENTAILMENT** - Hypothesis is fully supported by the premise
- **CONTRADICTION** - Hypothesis conflicts with the premise
- **NEUTRAL** - Cannot determine from premise alone

### confidence (required)

Rate your certainty (1-5 scale):

1. Very uncertain - guessing
2. Somewhat uncertain
3. Moderately confident
4. Confident
5. Very confident

### evidence_quality (optional)

Assess the evidence in the premise:

- **clear** - Explicit, unambiguous evidence
- **partial** - Some evidence, requires inference
- **ambiguous** - Unclear or contradictory
- **missing** - Required information absent

### reasoning (optional)

Brief explanation for your classification. Note: PII redaction is applied to this field.

## Queue Configuration

The CVL labeling queue uses Anvil's redundancy policy to ensure multiple independent labels per sample.

### Default Settings

```elixir
%{
  labels_per_sample: 3,
  assignment_timeout: 3600,  # 1 hour
  policy: :redundancy,
  policy_config: %{
    allow_same_labeler: false
  }
}
```

### Policy Details

- Each sample receives exactly 3 labels from different labelers
- Labelers cannot be assigned a sample they've already labeled
- Assignments expire after 1 hour if not completed
- Queue uses ETS storage by default (Postgres for production)

## Quality Filtering

Export pipeline applies quality filters:

### Agreement Threshold

Samples must achieve minimum inter-rater agreement:

```elixir
# Default: 0.80 (80% agreement)
export_training_data(min_agreement: 0.80)
```

Agreement is calculated as the percentage of labels matching the majority verdict.

### Minimum Labels

Samples must have minimum number of completed labels:

```elixir
# Default: 3 labels
export_training_data(min_labels: 3)
```

### Consensus Requirement

Optionally require clear majority verdict:

```elixir
export_training_data(consensus_required: true)
```

## PII Redaction

Clinical text exports are redacted using `MedlumLlm.PII.Clinical`:

### Redaction Modes

- **:standard** - High-confidence clinical identifiers (MRN, DOB, NPI, etc.)
- **:aggressive** - Standard + provider names, facilities, addresses
- **:none** - No redaction (trusted internal use only)

### Clinical PII Types

- Medical Record Numbers (MRN)
- Date of Birth (DOB)
- National Provider Identifier (NPI)
- DEA Numbers
- Medicare/Medicaid IDs
- Insurance IDs
- Medical dates (admission, discharge)
- Room/Bed numbers
- Provider names (aggressive mode)
- Facility names (aggressive mode)

## Forge Integration

### Publishing to Anvil

```elixir
# Publish Forge samples to Anvil queue
{:ok, count} = MedlumLlm.CVL.ForgeBridge.publish_to_anvil(
  forge_samples,
  "cvl_nli_training"
)
```

### Syncing Back to Forge

```elixir
# Sync labeled data back to Forge
{:ok, count} = MedlumLlm.CVL.ForgeBridge.sync_to_forge(
  "cvl_nli_training",
  min_labels: 3,
  min_agreement: 0.80
)
```

### Bridge Status

```elixir
status = MedlumLlm.CVL.ForgeBridge.status("cvl_nli_training")
# => %{
#      anvil_samples: 100,
#      complete_samples: 85,
#      total_labels: 255,
#      unique_labelers: 5,
#      synced_to_forge: 75
#    }
```

## Schema Versioning

CVL uses versioned schemas for reproducibility:

### Version History

- **1.0** - Initial: verdict + confidence
- **1.1** - Added: evidence_quality + reasoning

### Using Specific Versions

```elixir
# Get schema for specific version
schema = MedlumLlm.CVL.SchemaVersions.schema("1.0")

# Check version compatibility
MedlumLlm.CVL.SchemaVersions.valid_version?("1.1")
# => true

# Get field mapping between versions
mapping = MedlumLlm.CVL.SchemaVersions.field_mapping("1.0", "1.1")
# => %{
#      added: [:evidence_quality, :reasoning],
#      removed: [],
#      unchanged: [:verdict, :confidence]
#    }
```

## Labeling Guidelines

Access structured guidelines for labeler training:

```elixir
# Get full guidelines
guidelines = MedlumLlm.CVL.LabelingGuidelines.full_guidelines()

# Generate markdown documentation
markdown = MedlumLlm.CVL.LabelingGuidelines.to_markdown()

# Get verdict descriptions
descriptions = MedlumLlm.CVL.LabelingGuidelines.verdict_descriptions()

# Get common pitfalls
pitfalls = MedlumLlm.CVL.LabelingGuidelines.common_pitfalls()
```

## Monitoring & Quality Control

### Queue Statistics

```elixir
stats = MedlumLlm.CVL.LabelingQueue.stats()
# => %{
#      total_labels: 300,
#      total_assignments: 350,
#      completed_assignments: 300,
#      total_samples: 100,
#      unique_labelers: 5
#    }
```

### Agreement Metrics

```elixir
# Compute overall agreement
{:ok, score} = MedlumLlm.CVL.LabelingQueue.compute_agreement()

# Agreement for specific field
{:ok, score} = MedlumLlm.CVL.LabelingQueue.compute_agreement(field: "verdict")
```

### Export Quality Metrics

```elixir
metrics = MedlumLlm.CVL.ExportPipeline.quality_metrics()
# => %{
#      total_samples: 100,
#      complete_samples: 95,
#      high_agreement_samples: 80,
#      overall_agreement: 0.85,
#      verdict_distribution: %{
#        "ENTAILMENT" => 40,
#        "CONTRADICTION" => 25,
#        "NEUTRAL" => 30
#      }
#    }
```

## Best Practices

1. **Train labelers** using the guidelines before production labeling
2. **Start with calibration** - have all labelers label the same samples initially
3. **Monitor agreement** - investigate samples with low agreement
4. **Use versioned schemas** - lock schema version for each training batch
5. **Export with aggressive redaction** - always redact clinical text
6. **Verify exports** - use manifest hashes to ensure reproducibility

## Troubleshooting

### Low Agreement

If agreement scores are low:

1. Review common pitfalls with labelers
2. Check for ambiguous samples
3. Consider requesting additional labels
4. Use decision tree for calibration

### Missing Labels

If samples have fewer labels than expected:

1. Check assignment timeouts
2. Verify labeler availability
3. Review skip reasons
4. Increase labeler pool

### Export Failures

If exports fail:

1. Verify output directory exists
2. Check PII redaction patterns
3. Confirm minimum threshold settings
4. Review manifest for errors
