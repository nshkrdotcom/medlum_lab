# MedlumLlm

Medical AI library for clinical NLP evaluation and verification, built on the NSAI ecosystem.

[![Hex.pm](https://img.shields.io/hexpm/v/medlum_llm.svg)](https://hex.pm/packages/medlum_llm)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/medlum_llm)

## Features

### Chat & Embeddings
- Medical LLM chat via Ollama (BioMistral, OpenBioLLM, Meditron)
- Clinical text embeddings with batch processing
- Smart model routing based on clinical task type

### Clinical Verification Layer (CVL)
- 5-agent verification system for hallucination detection
- Medication verification (RxNorm)
- Lab value validation (LOINC)
- Ontology consistency (SNOMED-CT, ICD-10)
- Temporal logic checking
- Symptom-diagnosis mapping
- >85% accuracy target, >95% hallucination detection

### Medical Evaluation
- Dataset loading (MedQA, PubMedQA, MedMCQA, MMLU-Medical)
- Medical-specific metrics (hallucination recall, clinical safety score)
- Published baselines for validation
- Benchmark configurations with prompt templates

## Installation

```elixir
def deps do
  [
    {:medlum_llm, "~> 0.2.0"}
  ]
end
```

## Quick Start

### Chat with Medical LLMs

```elixir
alias MedlumLlm.Chat

# Simple chat
{:ok, response} = MedlumLlm.chat("What are the symptoms of diabetes?")

# With specific model
{:ok, response} = MedlumLlm.chat("Explain metformin mechanism", model: :biomistral_7b)

# Streaming
MedlumLlm.chat_stream("List side effects of lisinopril", fn chunk ->
  IO.write(chunk)
end)
```

### Clinical Verification (CVL)

```elixir
alias MedlumLlm.CVL.{MedicationAgent, LabAgent, Verifier}

# Verify a medication claim against source documents
claim = "Patient started on metformin 500mg twice daily"
context = %{
  conditions: [:diabetes],
  source_index: %{
    medications: [%{text: "metformin 500 mg BID", doc_id: "note-1"}]
  }
}

result = MedicationAgent.verify(claim, context)

result.verdict          #=> :entailment
result.confidence       #=> 0.95
result.explanations     #=> ["Medication 'metformin' supported by source documents"]

# Verify lab values
lab_claim = "Patient's HbA1c is 7.2%"
lab_context = %{
  source_index: %{
    labs: [%{text: "HbA1c 7.2%", doc_id: "lab-1"}]
  }
}

LabAgent.verify(lab_claim, lab_context)
#=> %{verdict: :entailment, explanations: ["Hemoglobin A1c: 7.2 % (high, ref: 4.0-5.6)"]}
```

### Medical Datasets

```elixir
alias MedlumLlm.Datasets

# List available datasets
MedlumLlm.available_datasets()
#=> [:medqa, :pubmedqa, :medmcqa, :mmlu_medical, :reasonmed]

# Load dataset
{:ok, samples} = MedlumLlm.load_dataset(:medqa, sample: 100)

# Access sample
sample = hd(samples)
sample.question  #=> "A 45-year-old woman..."
sample.options   #=> ["A. ...", "B. ...", ...]
sample.answer    #=> "B"
```

### Medical Metrics

```elixir
alias MedlumLlm.Eval.MedicalMetrics

# Standard metrics (delegated to eval_ex)
accuracy = MedicalMetrics.accuracy(predictions, samples)

# Confidence intervals (delegated to crucible_bench)
{lower, upper} = MedicalMetrics.wilson_ci(correct, total)

# Medical-specific metrics
recall = MedicalMetrics.hallucination_recall(cvl_preds, ground_truth)
precision = MedicalMetrics.hallucination_precision(cvl_preds, ground_truth)
safety = MedicalMetrics.clinical_safety_score(predictions, samples, cvl_results)
```

### Benchmarks & Baselines

```elixir
alias MedlumLlm.Eval.{Benchmarks, Baselines}

# Get benchmark configuration
{:ok, config} = Benchmarks.get(:medqa_zero_shot)

# Compare against published baselines
Baselines.format_comparison(:medqa, :openbio_8b, 0.74)
#=> "74.0% (-1.0% vs baseline 75.0%)"

Baselines.compare(:medqa, :openbio_8b, 0.74)
#=> :match (within 5%)
```

## Architecture

```
MedlumLlm (~2,000 LOC)
    |
    +-- Chat, Embedder, Router, Profile (existing)
    |
    +-- Datasets (thin wrapper over hf_datasets_ex)
    |       +-- Config (medical dataset configs)
    |       +-- Preprocessor (medical-specific normalization)
    |
    +-- Eval
    |       +-- MedicalMetrics (wraps eval_ex + medical-specific)
    |       +-- Benchmarks (configs only)
    |       +-- Baselines (published results)
    |       +-- Prompts (templates + parsers)
    |
    +-- CVL (Clinical Verification Layer)
    |       +-- Agent (behaviour)
    |       +-- MedicationAgent (weight: 1.5)
    |       +-- LabAgent (weight: 1.2)
    |       +-- OntologyAgent (weight: 1.0)
    |       +-- TemporalAgent (weight: 0.8)
    |       +-- DifferentialAgent (weight: 1.0)
    |       +-- Consensus (weighted voting via crucible_ensemble)
    |
    +-- Guardrails
            +-- Redactor (PHI redaction)
            +-- Audit (Telemetry-based logging)
            +-- Detectors.ClinicalPII (tiered PII patterns)
```

## CVL Agent Weights

| Agent | Weight | Rationale |
|-------|--------|-----------|
| MedicationAgent | 1.5 | Safety-critical, drug errors are dangerous |
| LabAgent | 1.2 | Objective values, high reliability |
| OntologyAgent | 1.0 | Standard reference |
| TemporalAgent | 0.8 | Often ambiguous temporal info |
| DifferentialAgent | 1.0 | Standard reference |

## NSAI Dependencies

MedlumLlm wraps these NSAI ecosystem libraries:

| Library | Purpose |
|---------|---------|
| `hf_datasets_ex` | HuggingFace dataset loading |
| `eval_ex` | Core metrics (accuracy, F1, BLEU) |
| `crucible_bench` | Statistical testing (Wilson CI, McNemar) |
| `crucible_harness` | Experiment orchestration |
| `crucible_ensemble` | Multi-agent consensus |
| `llm_guard` | Input/output guardrails |
| `forge` | Data pipelines |
| `anvil` | Human labeling |

## Medical Models

### Chat Models
- BioMistral-7B
- OpenBioLLM-8B
- Meditron-7B
- II-Medical-8B
- HuatuoGPT-o1-8B

### Embedding Models
- nomic-embed-text (768d)
- mxbai-embed-large (1024d)

## Supported Datasets

| Dataset | Task | Size | Description |
|---------|------|------|-------------|
| `:medqa` | MCQ | 12K | USMLE-style questions |
| `:pubmedqa` | Binary QA | 1K | PubMed abstracts |
| `:medmcqa` | MCQ | 187K | Indian medical exams |
| `:reasonmed` | Reasoning | 1.1M | Chain-of-thought |
| `:mmlu_medical` | MCQ | ~3K | Medical MMLU subjects |

## Examples

See `examples/` directory:

### Core Examples (require Ollama)
- `01_health_check.exs` - Connection and model discovery
- `02_embeddings.exs` - Clinical text embeddings and similarity
- `03_chat_biomistral.exs` - Chat with BioMistral-7B
- `04_chat_openbio.exs` - Chat with OpenBioLLM-8B
- `05_chat_meditron.exs` - Chat with Meditron-7B
- `06_clinical_use_cases.exs` - Real-world clinical NLP
- `07_model_comparison.exs` - Compare multiple models

### NSAI Integration Examples
- `datasets_example.exs` - Loading medical datasets
- `metrics_example.exs` - Medical metric calculations
- `benchmark_example.exs` - Running benchmarks
- `cvl_example.exs` - CVL verification workflows
- `evaluation_pipeline.exs` - End-to-end evaluation

```bash
# Run individual example
mix run examples/cvl_example.exs

# Run all NSAI examples
mix examples.nsai
```

## Documentation

Full documentation available at [HexDocs](https://hexdocs.pm/medlum_llm).

### Guides
- [Getting Started](guides/getting_started.md)
- [CVL Verification](guides/cvl.md)
- [Evaluation](guides/evaluation.md)
- [Datasets](guides/datasets.md)
- [HIPAA Compliance](guides/hipaa_compliance.md)
- [Redaction](guides/redaction.md)

### CVL Pipeline Guides
- [CVL Training Pipeline](guides/cvl_training_pipeline.md)
- [CVL Measurements](guides/cvl_measurements.md)
- [CVL Labeling](guides/cvl_labeling.md)
- [CVL Export](guides/cvl_export.md)

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run integration tests (requires Ollama)
mix test.integration

# Run all tests including integration
mix test.all

# Check NSAI library versions
mix check.nsai
```

## GPU Memory Guide for RTX 5060 Ti (16GB)

### Safe to Run (fits in 16GB):
- All embedding models
- BioMistral-7B (~4GB)
- OpenBioLLM-8B (~5GB)
- Meditron-7B (~4GB)

### Will NOT Fit (requires >40GB):
- OpenBioLLM-70B
- Meditron-70B

## Configuration

```elixir
# config/config.exs
config :medlum_llm,
  ollama_host: "http://localhost:11434",
  chat_model: "hf.co/BioMistral/BioMistral-7B-GGUF",
  embed_model: "nomic-embed-text"

# NSAI evaluation settings
config :medlum_llm,
  enable_eval: true,
  eval_default_retention: :errors_only,
  eval_results_dir: "results/"

# Production ontology modules (replace stubs)
config :medlum_llm,
  rxnorm_module: MedOntologyEx.RxNorm,
  loinc_module: MedOntologyEx.LOINC,
  snomed_module: MedOntologyEx.SNOMED,
  icd10_module: MedOntologyEx.ICD10,
  differential_db_module: MedOntologyEx.DifferentialDB
```

## License

MIT License - See [LICENSE](LICENSE) for details.

## Related Projects

- [Ollixir](https://hex.pm/packages/ollixir) - Elixir Ollama client
- [NSAI](https://github.com/North-Shore-AI) - Neural System AI ecosystem
