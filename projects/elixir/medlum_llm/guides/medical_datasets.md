# Medical Datasets Guide

MedlumLlm provides comprehensive support for loading and managing medical datasets with full lineage tracking, quality validation, and reproducibility features.

## Overview

The medical datasets module wraps HuggingFace medical datasets with DatasetsEx features:

- **Lineage Tracking**: Every dataset load creates an artifact reference for provenance tracking
- **Medical Metadata**: Extended metadata schema including clinical area, PHI status, and baselines
- **Format Validation**: MCQ, Binary QA, NER, CVL, and Reasoning format validators
- **Reproducibility**: Revision pinning and seeded operations

## Loading Medical Datasets

### Available Datasets

| Dataset | Task | Clinical Area | Description |
|---------|------|---------------|-------------|
| `:medqa` | MCQ | USMLE | MedQA USMLE-style questions |
| `:medmcqa` | MCQ | General Medicine | Indian medical entrance exam |
| `:pubmedqa` | Binary QA | Biomedical Research | PubMed research questions |
| `:mmlu_clinical` | MCQ | Clinical Knowledge | MMLU clinical subset |
| `:mmlu_medical_genetics` | MCQ | Medical Genetics | MMLU genetics subset |
| `:mmlu_professional_medicine` | MCQ | Professional Medicine | MMLU professional subset |
| `:medical_o1` | Reasoning | Medical Reasoning | Chain-of-thought reasoning |
| `:ncbi_disease` | NER | Biomedical NER | Disease entity recognition |

### Basic Loading

```elixir
# Load MedQA dataset
{:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa)

# Load with options
{:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa,
  split: "test",
  limit: 100
)

# List available datasets
MedlumLlm.Datasets.Loaders.list_datasets()
# => [:medqa, :medmcqa, :pubmedqa, ...]
```

### Loading Options

| Option | Type | Description |
|--------|------|-------------|
| `:split` | String | Dataset split (default: from config) |
| `:limit` | Integer | Limit number of samples |
| `:streaming` | Boolean | Use streaming mode (default: false) |
| `:revision` | String | Pin HuggingFace revision for reproducibility |
| `:cache` | Boolean | Use cache (default: true) |
| `:token` | String | HuggingFace API token for gated datasets |

### Reproducibility with Revision Pinning

For reproducible experiments, always pin the dataset revision:

```elixir
{:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa,
  split: "test",
  revision: "abc123def"  # Pin to specific commit
)

# The revision is tracked in metadata
dataset.metadata.hf_revision
# => "abc123def"
```

## Medical Metadata Schema

Every loaded medical dataset includes extended metadata:

```elixir
%{
  domain: :medical,
  clinical_area: "usmle",              # Clinical specialization
  task: :mcq,                          # Task type
  data_license: "MIT",                 # License
  phi_status: :none,                   # PHI handling
  access_level: :public,               # Access restrictions
  hf_repo: "bigbio/med_qa",           # HuggingFace repo
  hf_revision: nil,                    # Pinned revision
  hf_split: "test",                    # Split name
  loaded_at: ~U[2026-01-25 10:00:00Z], # Load timestamp
  baselines: %{                        # Known baselines
    "GPT-4" => 86.1,
    "Med-PaLM 2" => 86.5
  },
  sample_count: 1273                   # Number of samples
}
```

### PHI Status Values

| Status | Description |
|--------|-------------|
| `:none` | No PHI present |
| `:synthetic` | Synthetic/generated data |
| `:deidentified` | De-identified clinical data |
| `:phi` | Contains protected health information |

### Access Levels

| Level | Description |
|-------|-------------|
| `:public` | Publicly available |
| `:gated` | Requires HuggingFace approval |
| `:private` | Private/internal only |

## Lineage Tracking

### Creating Artifact References

```elixir
{:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa)

# Create artifact reference for lineage
ref = DatasetsEx.artifact_ref(dataset)

# Reference includes:
# - artifact_id: Unique identifier
# - type: "dataset"
# - uri: "datasets_ex://medqa"
# - checksum: SHA-256 hash
# - metadata: Dataset metadata
```

### Building Lineage Graphs

```elixir
# Load source dataset
{:ok, medqa} = MedlumLlm.Datasets.Loaders.load(:medqa)
medqa_ref = DatasetsEx.artifact_ref(medqa)

# Filter to specific subject
filtered = DatasetsEx.Transform.filter(medqa, fn item ->
  item.subject == "pharmacology"
end)
filtered_ref = DatasetsEx.artifact_ref(filtered)

# Create provenance edge
edge = DatasetsEx.lineage_edge(medqa_ref, filtered_ref,
  relationship: "filtered_from",
  metadata: %{filter: "subject == pharmacology"}
)
```

### Medical Relationship Types

| Relationship | Description |
|--------------|-------------|
| `derived_from` | Generic derivation |
| `preprocessed_from` | Data preprocessing |
| `filtered_from` | Subset extraction |
| `augmented_from` | Data augmentation |
| `validated_against` | CVL validation |
| `trained_on` | Model training |
| `evaluated_on` | Evaluation run |
| `exported_from` | External use export |

## Quality Validation

### Format-Specific Validation

```elixir
alias MedlumLlm.Datasets.Validators

# Validate MCQ format
{:ok, report} = Validators.validate_mcq(dataset)

# Report structure:
%{
  valid: true,
  total_items: 100,
  valid_items: 100,
  invalid_items: 0,
  errors: [],
  warnings: []
}
```

### Full Quality Check

```elixir
{:ok, report} = Validators.full_quality_check(dataset, :mcq)

# Comprehensive report includes:
# - format_validation: Format-specific validation
# - duplicates: Duplicate detection
# - distribution: Label distribution analysis
# - profile: Text statistics and vocabulary
# - overall_valid: Combined validity check
```

### Custom Validation Checks

```elixir
# Check for answer leakage
custom_check = &MedlumLlm.Datasets.Validators.check_answer_not_in_question/1

{:ok, report} = Validators.validate_mcq(dataset,
  custom_checks: [custom_check]
)
```

## Data Format Reference

### MCQ Format

```elixir
%{
  id: "medqa_001",
  question: "What is the mechanism of action of metformin?",
  options: [
    "Increases insulin secretion",
    "Decreases hepatic gluconeogenesis",
    "Blocks glucose absorption",
    "Increases insulin sensitivity"
  ],
  correct_answer: "B",        # A/B/C/D or 0-3
  subject: "pharmacology",    # Optional
  explanation: "..."          # Optional
}
```

### Binary QA Format

```elixir
%{
  id: "pubmedqa_001",
  question: "Is aspirin effective for preventing heart attacks?",
  context: "Clinical evidence shows that low-dose aspirin...",
  answer: "yes",              # yes/no/maybe
  explanation: "..."          # Optional
}
```

### NER Format

```elixir
%{
  id: "ncbi_001",
  text: "The patient has diabetes mellitus type 2.",
  entities: [
    %{
      text: "diabetes mellitus type 2",
      type: "DISEASE",
      start: 16,
      end_pos: 40
    }
  ]
}
```

### Reasoning Format

```elixir
%{
  id: "medical_o1_001",
  question: "Why is insulin required in type 1 diabetes?",
  thinking: "Let me analyze this step by step...",
  answer: "Because the pancreas cannot produce insulin...",
  subject: "endocrinology"
}
```

## Working with Baselines

Access published baseline performance:

```elixir
alias MedlumLlm.Datasets.Metadata

config = MedlumLlm.Datasets.Loaders.get_config(:medqa)
metadata = Metadata.build(config, %{hf_split: "test"})

# Get baseline for specific model
{:ok, accuracy} = Metadata.get_baseline(metadata, "GPT-4")
# => {:ok, 86.1}

# Check if baseline exists
Metadata.get_baseline(metadata, "Unknown Model")
# => :not_available
```

## Versioning Medical Datasets

```elixir
# Load and version a dataset
{:ok, medqa} = MedlumLlm.Datasets.Loaders.load(:medqa, split: "test")
{:ok, versioned} = DatasetsEx.version(medqa, "v1.0.0")

# Load specific version later
{:ok, dataset} = DatasetsEx.load_version("medqa", "v1.0.0")

# Get version history
DatasetsEx.lineage("medqa")
# => [%{version: "v1.0.0", hash: "...", created_at: ...}]
```

## Best Practices

### 1. Always Pin Revisions for Experiments

```elixir
{:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa,
  split: "test",
  revision: "main"  # Or specific commit hash
)
```

### 2. Validate Before Training

```elixir
{:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa)

# Full quality check
{:ok, report} = Validators.full_quality_check(dataset, :mcq)

if report.overall_valid do
  # Proceed with training
else
  # Review report.errors
end
```

### 3. Track Lineage for Reproducibility

```elixir
# Create artifact reference
ref = DatasetsEx.artifact_ref(dataset)

# Store ref.artifact_id with experiment results
experiment_metadata = %{
  dataset_artifact_id: ref.artifact_id,
  dataset_checksum: ref.checksum,
  model: "my_model_v1"
}
```

### 4. Use Stratified Splits

```elixir
{train, test} = DatasetsEx.stratified_split(dataset,
  label_key: :correct_answer,
  ratio: 0.8,
  seed: 42
)
```

## Integration with MedlumLlm

MedlumLlm medical datasets are designed to work seamlessly with MedlumLlm evaluation:

```elixir
# Load dataset
{:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa, split: "test")

# Validate format
{:ok, _} = MedlumLlm.Datasets.Validators.validate_mcq(dataset)

# Create artifact reference for lineage
ref = DatasetsEx.artifact_ref(dataset)

# Use with MedlumLlm evaluation
# (See MedlumLlm evaluation documentation)
```

## See Also

- [CVL Training Guide](cvl_training.md) - Training data for Clinical Verification Layer
- [MedlumLlm README](../README.md) - Main library documentation
- [Lineage IR Documentation](https://hexdocs.pm/lineage_ir) - Artifact and provenance types
