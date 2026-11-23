# Getting Started with MedlumLlm

This guide will help you get started with MedlumLlm for medical AI evaluation and verification.

## Prerequisites

- Elixir 1.14+
- Ollama installed and running (for chat/embeddings)
- HuggingFace account (for dataset access, optional)

## Installation

Add MedlumLlm to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:medlum_llm, "~> 0.2.0"}
  ]
end
```

Then run:

```bash
mix deps.get
mix compile
```

## Configuration

Create or update `config/config.exs`:

```elixir
config :medlum_llm,
  ollama_host: "http://localhost:11434",
  chat_model: "hf.co/BioMistral/BioMistral-7B-GGUF",
  embed_model: "nomic-embed-text"

# Optional: NSAI evaluation settings
config :medlum_llm,
  enable_eval: true,
  eval_default_retention: :errors_only,
  eval_results_dir: "results/"

# Optional: HuggingFace token for dataset access
config :hf_datasets_ex,
  token: System.get_env("HF_TOKEN")
```

## Setting Up Ollama

### 1. Install Ollama

```bash
# Linux/WSL
curl -fsSL https://ollama.ai/install.sh | sh

# Start the server
ollama serve
```

### 2. Pull Medical Models

```bash
# Required for embeddings
ollama pull nomic-embed-text

# Text generation models (choose based on your needs)
ollama pull hf.co/BioMistral/BioMistral-7B-GGUF      # Recommended start
ollama pull hf.co/MoMonir/Llama3-OpenBioLLM-8B-GGUF  # Best reasoning
ollama pull hf.co/TheBloke/meditron-7B-GGUF          # Evidence-based
```

## Verify Installation

Start IEx and test:

```elixir
iex -S mix

# Check Ollama connection
MedlumLlm.health_check()
#=> :ok

# Test chat (requires Ollama with a model pulled)
{:ok, response} = MedlumLlm.chat("What is hypertension?")

# Test embeddings
{:ok, embedding} = MedlumLlm.embed("chest pain")

# List available datasets
MedlumLlm.available_datasets()
#=> [:medqa, :pubmedqa, :medmcqa, :reasonmed, :mmlu_medical]

# List available benchmarks
MedlumLlm.Eval.Benchmarks.list()
#=> [:medqa_zero_shot, :medqa_few_shot, :medqa_cot, ...]

# Check NSAI library integration
MedlumLlm.Integration.VersionCheck.check_all()
#=> :ok
```

Or via mix alias:

```bash
mix check.nsai
```

## Quick Examples

### Chat with Medical LLMs

```elixir
# Simple query
{:ok, response} = MedlumLlm.chat("What are the symptoms of myocardial infarction?")
IO.puts(response)

# With specific model
{:ok, response} = MedlumLlm.chat(
  "Explain the pathophysiology of diabetes",
  model: :openbio_8b
)

# Multi-turn conversation
messages = [
  %{role: "user", content: "Patient has chest pain radiating to left arm"},
  %{role: "assistant", content: "This presentation suggests possible ACS..."},
  %{role: "user", content: "ECG shows ST elevation in V1-V4"}
]
{:ok, response} = MedlumLlm.chat_messages(messages)
```

### Clinical Embeddings

```elixir
# Generate embedding
{:ok, embedding} = MedlumLlm.embed("Patient presents with acute chest pain")

# Semantic similarity
{:ok, similarity} = MedlumLlm.similarity("heart attack", "myocardial infarction")
#=> {:ok, 0.89}

# Find similar documents
corpus = ["chest pain", "leg fracture", "cardiac arrest", "headache"]
{:ok, results} = MedlumLlm.Embedder.find_similar("heart problems", corpus, top_k: 2)
#=> {:ok, [{"cardiac arrest", 0.85}, {"chest pain", 0.72}]}
```

### CVL Verification

```elixir
alias MedlumLlm.CVL.MedicationAgent

# Verify a medication claim
claim = "Patient started on metformin 500mg twice daily"
context = %{
  conditions: [:diabetes],
  source_index: %{
    medications: [%{text: "metformin 500 mg BID", doc_id: "note-1"}]
  }
}

result = MedicationAgent.verify(claim, context)
IO.puts("Verdict: #{result.verdict}")       #=> :entailment
IO.puts("Confidence: #{result.confidence}") #=> 0.95
```

### Loading Datasets

```elixir
# Load MedQA test set (first 100 samples)
{:ok, samples} = MedlumLlm.load_dataset(:medqa, sample: 100)

# Examine a sample
sample = hd(samples)
IO.puts("Question: #{sample.question}")
IO.puts("Options: #{inspect(sample.options)}")
IO.puts("Answer: #{sample.answer}")
```

### Running Benchmarks

```elixir
alias MedlumLlm.Eval.{Benchmarks, Baselines}

# Get benchmark configuration
{:ok, config} = Benchmarks.get(:medqa_zero_shot)
IO.puts("Benchmark: #{config.name}")
IO.puts("Dataset: #{config.dataset}")

# Compare your results against baselines
my_accuracy = 0.74
comparison = Baselines.format_comparison(:medqa, :openbio_8b, my_accuracy)
IO.puts(comparison)
#=> "74.0% (-1.0% vs baseline 75.0%)"
```

## Model Selection Guide

| Use Case | Recommended Model | VRAM |
|----------|-------------------|------|
| General medical Q&A | BioMistral-7B | ~4GB |
| Differential diagnosis | OpenBioLLM-8B | ~5GB |
| Evidence-based queries | Meditron-7B | ~4GB |
| Clinical note search | nomic-embed-text | <1GB |
| High-precision similarity | mxbai-embed-large | <2GB |

## Next Steps

- [CVL Guide](cvl.md) - Learn about clinical verification and hallucination detection
- [Evaluation Guide](evaluation.md) - Learn about medical benchmarks and metrics
- [Datasets Guide](datasets.md) - Detailed dataset loading and preprocessing
- [HIPAA Compliance Guide](hipaa_compliance.md) - PHI handling and redaction
- Check the `examples/` directory for complete examples

## Running Examples

```bash
# Core examples (require Ollama)
mix run examples/02_embeddings.exs
mix run examples/03_chat_biomistral.exs

# NSAI integration examples
mix run examples/datasets_example.exs
mix run examples/cvl_example.exs

# Run all NSAI examples
mix examples.nsai
```

## Troubleshooting

### Ollama Connection Failed

```elixir
# Check if Ollama is running
MedlumLlm.health_check()
#=> {:error, :econnrefused}
```

**Solution**: Start Ollama with `ollama serve`

### Model Not Found

```elixir
# Pull the model
MedlumLlm.pull_model(:biomistral_7b)

# Or manually
# ollama pull hf.co/BioMistral/BioMistral-7B-GGUF
```

### Out of VRAM

If you get VRAM errors, use smaller models or free memory:

```bash
# Stop current model
ollama stop biomistral:7b

# Use a smaller model
```

### NSAI Libraries Not Found

```elixir
MedlumLlm.Integration.VersionCheck.check_all()
#=> {:error, [:eval_ex, :crucible_bench]}
```

**Solution**: Ensure all dependencies are installed:

```bash
mix deps.get
mix deps.compile
```

## Getting Help

- [GitHub Issues](https://github.com/medlum/medlum_llm/issues)
- [HexDocs](https://hexdocs.pm/medlum_llm)
- [Examples Directory](../examples/)
