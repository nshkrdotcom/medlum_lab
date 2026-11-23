# MedlumLlm Examples

This directory contains live, working examples demonstrating MedlumLlm's capabilities with medical LLMs and clinical embeddings.

## Prerequisites

### 1. Install Ollama

```bash
# Linux/WSL
curl -fsSL https://ollama.ai/install.sh | sh

# Start the server
ollama serve
```

### 2. Pull Required Models

**For embeddings (required for most examples):**
```bash
ollama pull nomic-embed-text
```

**For text generation (choose based on your needs):**
```bash
# Recommended starting point (~4GB VRAM)
ollama pull hf.co/BioMistral/BioMistral-7B-GGUF

# Alternative medical LLMs
ollama pull hf.co/MoMonir/Llama3-OpenBioLLM-8B-GGUF   # ~5GB VRAM
ollama pull hf.co/TheBloke/meditron-7B-GGUF          # ~4GB VRAM
```

### 3. Verify Setup

```bash
# Check Ollama is running
curl http://localhost:11434/api/tags

# Or use MedlumLlm
mix run examples/01_health_check.exs
```

## Examples Overview

### Core Examples (require Ollama)

| Example | Description | Required Models |
|---------|-------------|-----------------|
| `01_health_check.exs` | Connection and model discovery | Any |
| `02_embeddings.exs` | Clinical text embeddings | nomic-embed-text |
| `03_chat_biomistral.exs` | Chat with BioMistral-7B | BioMistral-7B-GGUF |
| `04_chat_openbio.exs` | Chat with OpenBioLLM-8B | OpenBioLLM-8B-GGUF |
| `05_chat_meditron.exs` | Chat with Meditron-7B | meditron-7B-GGUF |
| `06_clinical_use_cases.exs` | Real-world clinical NLP | nomic-embed-text |
| `07_model_comparison.exs` | Compare multiple models | Any medical LLM |

### Advanced Examples (REAL inference, require Ollama)

| Example | Description | Required Models |
|---------|-------------|-----------------|
| `08_model_registry.exs` | Explore 20+ model catalog | None (metadata only) |
| `09_multi_model_chat.exs` | Compare responses across models | BioMistral, MedLLaMA2, Meditron |
| `10_embedding_comparison.exs` | Clinical embedding analysis | nomic-embed-text |
| `11_hardware_aware.exs` | Hardware-aware model selection | Any models |
| `12_clinical_pipeline.exs` | Real end-to-end NLP pipeline | nomic-embed-text + any chat model |

### CrucibleHarness Experiment Examples

These examples demonstrate how to use CrucibleHarness for systematic medical AI benchmarking.

| Example | Description | Required Dependencies |
|---------|-------------|----------------------|
| `13_crucible_experiment.exs` | Define and run a medical Q&A experiment | `crucible_harness ~> 0.3` |
| `14_experiment_templates.exs` | Reusable templates for MCQ, summarization, CVL, and streaming | `crucible_harness ~> 0.3` |

**Key DSL Pattern:**
```elixir
conditions [
  %{name: "biomistral_7b", fn: &evaluate_biomistral/1},
  %{name: "openbio_8b", fn: &evaluate_openbio/1}
]
```

Each condition's `:fn` takes a single sample and returns a map with metric keys.

## Running Examples

### Individual Examples

```bash
# From the medlum_llm directory
mix run examples/01_health_check.exs
mix run examples/02_embeddings.exs
mix run examples/03_chat_biomistral.exs
# ... etc
```

### Run All Examples

```bash
./examples/run_all.sh
```

Or run specific categories:
```bash
./examples/run_all.sh --embeddings-only
./examples/run_all.sh --chat-only
```

## Example Details

### 01. Health Check

Verifies Ollama connectivity and lists available models. Good starting point to ensure your setup is working.

**What you'll learn:**
- How to check Ollama connection
- How to list available models
- How to inspect model metadata

### 02. Embeddings

Demonstrates clinical text embeddings for semantic search and similarity.

**What you'll learn:**
- Single and batch embedding generation
- Semantic similarity between clinical terms
- Finding similar documents (semantic search)

**Sample output:**
```
heart attack <-> myocardial infarction  0.892 ████████████████████
chest pain   <-> cardiac symptoms       0.756 ███████████████
diabetes     <-> fracture               0.234 ████
```

### 03. Chat with BioMistral

Text generation with BioMistral-7B, a medical domain fine-tuned model.

**What you'll learn:**
- Simple medical Q&A
- Multi-turn conversations
- Custom system prompts
- Clinical text completion

### 04. Chat with OpenBioLLM

Medical reasoning and differential diagnosis with OpenBioLLM-8B.

**What you'll learn:**
- Differential diagnosis generation
- Drug interaction analysis
- Lab value interpretation
- Clinical guideline queries

### 05. Chat with Meditron

Evidence-based medicine queries with Meditron-7B.

**What you'll learn:**
- Evidence-based medicine queries
- Treatment guideline summaries
- Medical concept explanations
- Screening recommendations

### 06. Clinical Use Cases

Comprehensive demonstration of real-world clinical NLP applications.

**What you'll learn:**
- Semantic search over clinical notes
- Automatic ICD-10 code suggestion
- Finding similar patient cases
- Clustering notes by medical specialty

### 07. Model Comparison

Side-by-side comparison of different medical LLMs.

**What you'll learn:**
- How different models respond to the same query
- Response time comparisons
- When to use which model

### 08. Model Registry

Explore the hierarchical model catalog with 20+ models organized by category, tier, and domain.

**What you'll learn:**
- Query models by category (chat, embed, ner, pii)
- Filter by quality tier (fast, balanced, accurate)
- Hardware-constrained selection (fits_vram)
- Task-based model recommendations
- NER models by domain (disease, pharma, chemical, anatomy)

### 09. Multi-Model Chat Comparison

**REAL INFERENCE** - Compare responses across multiple medical LLMs.

**What you'll learn:**
- Query the same medical question to 5+ models
- Compare real inference times
- Analyze response quality differences
- Graceful handling when models aren't available

**Sample output:**
```
Performance Ranking:
1. BioMistral-7B: 8234ms
2. MedLLaMA2: 9102ms
3. Meditron-7B: 9847ms
```

### 10. Embedding Comparison

**REAL INFERENCE** - Clinical text embeddings and semantic similarity.

**What you'll learn:**
- Generate real embeddings for clinical terms
- Calculate semantic similarity between medical concepts
- Batch embedding performance
- Embedding dimension analysis

**Sample output:**
```
heart attack <-> myocardial infarction  0.892 ||||||||||||||||||||
diabetes     <-> fracture               0.234 ||||
```

### 11. Hardware-Aware Model Selection

**REAL INFERENCE** - Discover and select models based on hardware.

**What you'll learn:**
- Query all locally available models
- Categorize by VRAM requirements
- Identify medical-specific models
- Select appropriate model for task and hardware

### 12. Clinical NLP Pipeline

**REAL INFERENCE** - Complete end-to-end clinical document processing.

**What you'll learn:**
- Real embedding generation for document corpus
- Semantic search to find relevant documents
- LLM summarization of clinical notes
- Performance timing for each pipeline step
- Production-ready pipeline pattern (no mocks)

## GPU Memory Requirements

| Model | VRAM Required | Fits 16GB GPU? |
|-------|---------------|----------------|
| nomic-embed-text | <1GB | YES |
| BioMistral-7B | ~4GB | YES |
| OpenBioLLM-8B | ~5GB | YES |
| Meditron-7B | ~4GB | YES |
| OpenBioLLM-70B | ~40GB | NO |
| Meditron-70B | ~40GB | NO |

## Troubleshooting

### "Cannot connect to Ollama"

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# If not, start it
ollama serve
```

### "Model not found"

```bash
# List available models
ollama list

# Pull the required model
ollama pull nomic-embed-text
```

### Out of memory errors

Try a smaller quantization:
```bash
# Instead of default, use Q4_K_M
ollama pull hf.co/BioMistral/BioMistral-7B-GGUF:Q4_K_M
```

### Slow responses

First response is slower due to model loading. Subsequent responses are faster. Consider running a warm-up query first.

## Custom Examples

Create your own examples by following this pattern:

```elixir
#!/usr/bin/env elixir

Logger.configure(level: :warning)

# Check connection
case MedlumLlm.health_check() do
  :ok -> :ok
  {:error, _} ->
    IO.puts("Ollama not running")
    System.halt(1)
end

# Your code here
{:ok, response} = MedlumLlm.chat("Your medical query")
IO.puts(response)
```

Run with: `mix run your_example.exs`

## NSAI Integration Examples (New in v0.2.0)

These examples demonstrate the NSAI ecosystem integration added in prompts 180-189:
medical datasets, evaluation metrics, benchmarks, and the CVL verification system.

### NSAI Examples Overview

| Example | Description | NSAI Libraries |
|---------|-------------|----------------|
| `datasets_example.exs` | Load and explore medical datasets | `hf_datasets_ex` |
| `metrics_example.exs` | Medical-specific evaluation metrics | `eval_ex`, `crucible_bench` |
| `benchmark_example.exs` | Benchmark configs and baselines | `crucible_harness` |
| `cvl_example.exs` | Clinical Verification Layer | 5-agent CVL system |
| `evaluation_pipeline.exs` | End-to-end evaluation workflow | All NSAI stack |

### Running NSAI Examples

```bash
# Individual examples
mix example.datasets     # Dataset loading
mix example.metrics      # Medical metrics
mix example.benchmarks   # Benchmark configs
mix example.cvl          # CVL verification
mix example.pipeline     # End-to-end pipeline

# Run all NSAI examples
mix examples.nsai
```

### datasets_example.exs

Load and explore medical datasets from HuggingFace.

**What you'll learn:**
- List available medical datasets (MedQA, PubMedQA, MedMCQA, etc.)
- Get dataset configurations and descriptions
- Load datasets with options (split, limit, streaming)
- Check credential requirements
- Understand dataset task types (MCQ, binary QA, reasoning)

**Sample output:**
```
Available Medical Datasets:
   - medqa
   - pubmedqa
   - medmcqa
   - reasonmed
   - mmlu_medical
```

### metrics_example.exs

Calculate medical-specific evaluation metrics.

**What you'll learn:**
- Basic accuracy with confidence intervals (Wilson CI)
- F1 scores and exact match
- CVL hallucination metrics (recall, precision, F1)
- McNemar test for model comparison
- Clinical safety score calculation

**Sample output:**
```
Wilson Confidence Interval:
   95% CI: [41.6%, 88.4%]

CVL Hallucination Detection:
   Recall: 66.7%
   Precision: 66.7%
```

### benchmark_example.exs

Explore benchmark configurations and published baselines.

**What you'll learn:**
- List available benchmarks (MedQA zero-shot, few-shot, CoT, etc.)
- Get benchmark configurations
- Compare against published baselines (GPT-4, Med-PaLM 2, etc.)
- Use prompt templates for MCQ, binary QA, reasoning
- Parse model responses

**Sample output:**
```
MedQA Published Baselines:
   ii_medical_8b          88.0%        II-Medical HF Card
   gpt4                   86.0%        OpenAI GPT-4 Technical Report
   medpalm2               85.0%        Google Med-PaLM 2 Paper
```

### cvl_example.exs

Clinical Verification Layer for hallucination detection.

**What you'll learn:**
- List CVL agents and their weights
- Verify claims with individual agents (Medication, Lab, Ontology, Temporal, Differential)
- Run full consensus verification
- Understand verdict semantics (entailment, contradiction, neutral)
- Source-grounded verification

**Sample output:**
```
CVL Agents:
   medication_agent       1.5          RxNorm drug verification
   lab_agent              1.2          LOINC lab value validation
   ontology_agent         1.0          SNOMED-CT/ICD-10 terminology
   ...

Verification Result:
   Verdict: ENTAILMENT
   Confidence: 0.85
```

### evaluation_pipeline.exs

Complete end-to-end evaluation workflow.

**What you'll learn:**
- Load benchmark configuration
- Load or create test samples
- Run model evaluation (simulated or real)
- Calculate metrics with confidence intervals
- Compare against published baselines
- CVL verification of model outputs
- Generate summary reports

**Sample output:**
```
EVALUATION SUMMARY
------------------------------------------
Model: biomistral_7b
Benchmark: MedQA Zero-Shot
Samples: 10

ACCURACY
  Score: 70.0%
  95% CI: [41.6%, 88.4%]
  Baseline: 70.0% (+9.0% vs baseline 61.0%)
  Status: above
```

## CVL Pipeline Example

The existing `cvl_pipeline_example.exs` demonstrates the CVL training data pipeline
using Forge for processing evaluation failures into NLI training data.

**What you'll learn:**
- Run the full CVL training pipeline
- Process individual pipeline stages
- Compute CVL agent measurements
- Calculate consensus and confidence scores
