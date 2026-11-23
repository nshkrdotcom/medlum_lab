# ElixirBioClinicalbert

Clinical text embeddings using [Bio_ClinicalBERT](https://huggingface.co/emilyalsentzer/Bio_ClinicalBERT) via [Ollixir](https://hex.pm/packages/ollixir) and Ollama.

## Prerequisites

1. **Ollama** must be installed and running:
   ```bash
   # Install Ollama (see https://ollama.ai)
   curl -fsSL https://ollama.ai/install.sh | sh

   # Start the server
   ollama serve
   ```

2. **Pull an embedding model**:
   ```bash
   ollama pull nomic-embed-text
   ```

## Setup

```bash
cd elixir_bio_clinicalbert
mix deps.get
mix compile
```

## Run the Example

```bash
mix run examples/clinical_embeddings.exs
```

Expected output:
```
=== Clinical Text Embeddings with Bio_ClinicalBERT ===

1. Health Check
---------------
Status: Connected to Ollama

2. Model Info
-------------
Model: nomic-embed-text
Family: nomic-bert
Parameters: 137M
Quantization: F16

3. Single Embedding
-------------------
Text: Patient presents with acute chest pain radiating to left arm
Dimensions: 768
First 3 values: [0.037419803, 0.013468649, -0.15104397]

4. Batch Embeddings
-------------------
Processed 3 texts:
  - "Myocardial infarction with ST elevation" -> 768 dims
  - "Type 2 diabetes mellitus uncontrolled" -> 768 dims
  - "Acute appendicitis requiring surgery" -> 768 dims

5. Clinical Term Similarity
---------------------------
  heart attack           <-> myocardial infarction  0.692 ██████████████
  chest pain             <-> thoracic discomfort    0.715 ██████████████
  broken leg             <-> fractured femur        0.671 █████████████
  heart attack           <-> broken leg             0.414 ████████

=== All functions exercised successfully ===
```

## Run Tests

```bash
# Unit tests only (mocked, no Ollama required)
mix test

# All tests including integration (requires Ollama)
mix test --include integration
```

## Usage in Your Code

```elixir
# Single embedding
{:ok, embedding} = ElixirBioClinicalbert.embed("chest pain")

# Batch embeddings
{:ok, embeddings} = ElixirBioClinicalbert.embed_batch(["text1", "text2"])

# Similarity between clinical terms
{:ok, similarity} = ElixirBioClinicalbert.similarity("heart attack", "myocardial infarction")
# => 0.693

# Health check
:ok = ElixirBioClinicalbert.health_check()

# Model info
{:ok, info} = ElixirBioClinicalbert.model_info()
```

## Configuration

In `config/config.exs`:

```elixir
config :elixir_bio_clinicalbert,
  ollama_host: "http://localhost:11434",
  model: "nomic-embed-text"
```

Or via environment variables:
```bash
export OLLAMA_HOST="http://localhost:11434"
export EMBEDDING_MODEL="nomic-embed-text"
```
