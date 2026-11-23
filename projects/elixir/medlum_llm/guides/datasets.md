# Working with Medical Datasets

This guide covers loading and using medical evaluation datasets with MedlumLlm.

## Quick Start

```elixir
# Load the MedQA test set
{:ok, dataset} = MedlumLlm.Datasets.load(:medqa)

# Iterate over samples
Enum.each(dataset, fn sample ->
  IO.puts("Q: #{sample.question}")
  IO.puts("A: #{sample.answer}")
end)
```

## Available Datasets

MedlumLlm provides access to 7 medical datasets:

| Dataset | Task | Size | Description |
|---------|------|------|-------------|
| `:medqa` | MCQ | 12K | USMLE-style medical questions |
| `:pubmedqa` | Binary QA | 1K | Yes/No/Maybe from PubMed abstracts |
| `:medmcqa` | MCQ | 187K | Indian medical entrance exam |
| `:reasonmed` | Reasoning | 1.1M | Chain-of-thought medical reasoning |
| `:mmlu_medical` | MCQ | ~3K | Medical MMLU subjects |
| `:n2c2_medication` | NER | ~1K | Medication extraction (requires credentials) |
| `:mimic_sum` | Summarization | 50K | Clinical note summaries (requires credentials) |

## Normalized Sample Format

All datasets are preprocessed to a consistent format, making it easy to write evaluation code that works across datasets:

```elixir
%{
  id: "unique_id",
  question: "A 45-year-old man presents with...",
  options: ["A. Diabetes", "B. Hypertension", "C. COPD", "D. Asthma"],
  answer: "A",
  explanation: "The patient's symptoms are consistent with...",
  subject: "cardiology",
  meta: %{original_id: "medqa_001", source: "medqa"}
}
```

### Format by Task Type

**MCQ datasets** (medqa, medmcqa, mmlu_medical):
```elixir
%{
  id: string,
  question: string,
  options: ["A. ...", "B. ...", "C. ...", "D. ..."],
  answer: "A" | "B" | "C" | "D",
  explanation: string | nil,
  subject: string | nil,
  meta: map
}
```

**Binary Q&A** (pubmedqa):
```elixir
%{
  id: string,
  question: string,
  context: string,
  options: ["yes", "no", "maybe"],
  answer: "yes" | "no" | "maybe",
  long_answer: string | nil,
  meta: map
}
```

**Reasoning** (reasonmed):
```elixir
%{
  id: string,
  question: string,
  reasoning: string,  # Chain-of-thought
  answer: string,
  meta: map
}
```

## Loading Options

### Split Selection

```elixir
# Load default split (test for most datasets)
{:ok, dataset} = MedlumLlm.Datasets.load(:medqa)

# Load specific split
{:ok, train} = MedlumLlm.Datasets.load(:medqa, split: "train")
{:ok, dev} = MedlumLlm.Datasets.load(:medqa, split: "dev")
```

### Sampling for Development

When iterating quickly, load a random sample:

```elixir
# Load 100 random samples
{:ok, dataset} = MedlumLlm.Datasets.load(:medqa, sample: 100, seed: 42)

# Sampling is deterministic - same seed = same samples
{:ok, ds1} = MedlumLlm.Datasets.load(:medqa, sample: 50, seed: 42)
{:ok, ds2} = MedlumLlm.Datasets.load(:medqa, sample: 50, seed: 42)
# ds1 and ds2 contain the same samples
```

### Limiting Results

Use `limit` for quick testing (works with streaming):

```elixir
# Take first 10 samples
{:ok, dataset} = MedlumLlm.Datasets.load(:medqa, limit: 10)
```

## Streaming Large Datasets

ReasonMed has 1.1 million samples. Always use streaming to avoid memory issues:

```elixir
# Stream ReasonMed without loading all into memory
{:ok, stream} = MedlumLlm.Datasets.load(:reasonmed, streaming: true, limit: 10_000)

stream
|> Stream.map(&process_sample/1)
|> Stream.each(&save_result/1)
|> Stream.run()
```

For large datasets, the `streaming` option is enabled by default based on dataset configuration.

## Loading All Splits

Load train, validation, and test splits in one call:

```elixir
{:ok, splits} = MedlumLlm.Datasets.load_all_splits(:medqa)

splits["train"]  # Training dataset
splits["dev"]    # Development dataset
splits["test"]   # Test dataset
```

## Filtering by Task

Find datasets for specific evaluation tasks:

```elixir
# MCQ evaluation datasets
MedlumLlm.Datasets.by_task(:mcq)
#=> [:medqa, :medmcqa, :mmlu_medical]

# Reasoning evaluation
MedlumLlm.Datasets.by_task(:reasoning)
#=> [:reasonmed]

# Binary Q&A
MedlumLlm.Datasets.by_task(:binary_qa)
#=> [:pubmedqa]
```

## Dataset Information

Get metadata about a dataset:

```elixir
{:ok, info} = MedlumLlm.Datasets.info(:medqa)
info.name           #=> "MedQA"
info.repo           #=> "openlifescienceai/medqa"
info.task           #=> :mcq
info.default_split  #=> "test"

# Human-readable description
{:ok, desc} = MedlumLlm.Datasets.describe(:medqa)
desc.total_samples  #=> 12723
desc.citation       #=> "Jin et al., 2021"
```

## Credentialed Datasets

Some datasets require HuggingFace credentials:

```elixir
# Check if credentials are needed
MedlumLlm.Datasets.requires_credentials?(:n2c2_medication)
#=> true

MedlumLlm.Datasets.requires_credentials?(:medqa)
#=> false
```

To use credentialed datasets:

1. Create a HuggingFace account
2. Request access to the dataset
3. Set your HuggingFace token:
   ```bash
   export HF_TOKEN=your_token_here
   ```

## Reproducibility

Pin dataset revisions for reproducible experiments:

```elixir
{:ok, dataset} = MedlumLlm.Datasets.load(:medqa,
  revision: "abc123...",
  seed: 42
)
```

## Integration with Evaluation

Use datasets with the evaluation framework:

```elixir
defmodule MyExperiment do
  alias MedlumLlm.Datasets

  def evaluate_model(model_fn) do
    {:ok, dataset} = Datasets.load(:medqa)

    results = Enum.map(dataset, fn sample ->
      prediction = model_fn.(sample.question, sample.options)
      correct = prediction == sample.answer

      %{
        id: sample.id,
        prediction: prediction,
        answer: sample.answer,
        correct: correct
      }
    end)

    accuracy = Enum.count(results, & &1.correct) / length(results)
    {accuracy, results}
  end
end
```

## Convenience API

The main `MedlumLlm` module exposes dataset functions:

```elixir
# Load a dataset
{:ok, dataset} = MedlumLlm.load_dataset(:medqa)

# List available datasets
MedlumLlm.available_datasets()
#=> [:medqa, :pubmedqa, :medmcqa, ...]
```

## Error Handling

```elixir
case MedlumLlm.Datasets.load(:unknown) do
  {:ok, dataset} ->
    # Process dataset
    Enum.each(dataset, &process/1)

  {:error, :not_found} ->
    IO.puts("Dataset not found")

  {:error, %MedlumLlm.Integration.Error{} = error} ->
    IO.puts("Loading failed: #{Exception.message(error)}")
end
```

## Best Practices

1. **Use streaming for large datasets** - ReasonMed and other large datasets should always be streamed
2. **Pin revisions for reproducibility** - Specify exact dataset versions for experiments
3. **Sample during development** - Use `sample: 100` when iterating
4. **Check credentials** - Some datasets require HuggingFace authentication
5. **Handle errors** - Dataset loading can fail due to network issues

## See Also

- [Integration Architecture](../docs/20260125/nsai_medlum_integration/medlum_llm/01_integration_architecture.md)
- [ADR-002: NSAI Integration](../docs/20260125/nsai_medlum_integration/medlum_llm/adrs/ADR-002-nsai-integration.md)
