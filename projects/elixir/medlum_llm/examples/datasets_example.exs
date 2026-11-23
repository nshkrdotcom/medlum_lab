#!/usr/bin/env elixir
# Dataset Loading Examples for MedlumLlm
#
# Run with: mix run examples/datasets_example.exs

alias MedlumLlm.Datasets
alias MedlumLlm.Datasets.Config

IO.puts("=== MedlumLlm Datasets Example ===\n")

# -----------------------------------------------------------------------------
# 1. List Available Datasets
# -----------------------------------------------------------------------------

IO.puts("1. Available Medical Datasets:")
datasets = Datasets.available()
for name <- datasets do
  IO.puts("   - #{name}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 2. Get Dataset Configuration
# -----------------------------------------------------------------------------

IO.puts("2. MedQA Configuration:")
case Config.get(:medqa) do
  {:ok, config} ->
    IO.puts("   Name: #{config.name}")
    IO.puts("   Repo: #{config.repo}")
    IO.puts("   Task: #{config.task}")
    IO.puts("   Default Split: #{config.default_split}")
    IO.puts("   Splits: #{inspect(config.splits)}")
    IO.puts("   Streaming: #{config.streaming}")
    IO.puts("   Requires Credentials: #{config.requires_credentials}")
  {:error, reason} ->
    IO.puts("   Error: #{inspect(reason)}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 3. Dataset Description
# -----------------------------------------------------------------------------

IO.puts("3. Dataset Information:")
case Datasets.describe(:medqa) do
  {:ok, info} ->
    IO.puts("   Name: #{info.name}")
    IO.puts("   Description: #{info.description}")
    IO.puts("   Task: #{info.task}")
    IO.puts("   Total Samples: #{info.total_samples}")
    IO.puts("   Streaming Recommended: #{info.streaming_recommended}")
    IO.puts("   Citation: #{info.citation}")
  {:error, reason} ->
    IO.puts("   Error: #{inspect(reason)}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 4. List Datasets by Task Type
# -----------------------------------------------------------------------------

IO.puts("4. Datasets by Task Type:")
for task <- [:mcq, :binary_qa, :reasoning, :ner, :summarization] do
  datasets = Datasets.by_task(task)
  if length(datasets) > 0 do
    IO.puts("   #{task}: #{inspect(datasets)}")
  end
end
IO.puts("")

# -----------------------------------------------------------------------------
# 5. Check Credential Requirements
# -----------------------------------------------------------------------------

IO.puts("5. Credential Requirements:")
for name <- Datasets.available() do
  requires = Datasets.requires_credentials?(name)
  status = if requires, do: "[REQUIRES AUTH]", else: "[PUBLIC]"
  IO.puts("   #{name}: #{status}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 6. Public Datasets (Safe for Automated Warmup)
# -----------------------------------------------------------------------------

IO.puts("6. Public Datasets (no auth required):")
for name <- Config.public_datasets() do
  {:ok, config} = Config.get(name)
  size_str = config.size
              |> Map.values()
              |> Enum.sum()
  IO.puts("   #{name}: ~#{size_str} samples")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 7. Load Dataset (with graceful fallback)
# -----------------------------------------------------------------------------

IO.puts("7. Loading MedQA (test split, limit 5):")

case Datasets.load(:medqa, split: "test", limit: 5) do
  {:ok, samples} ->
    samples_list = Enum.to_list(samples)
    IO.puts("   Loaded #{length(samples_list)} samples")

    if length(samples_list) > 0 do
      sample = hd(samples_list)
      IO.puts("   First sample keys: #{inspect(Map.keys(sample))}")

      if sample[:question] do
        question = String.slice(sample.question, 0..80)
        IO.puts("   Question: #{question}...")
      end

      if sample[:options] do
        IO.puts("   Options count: #{length(sample.options)}")
      end

      if sample[:answer] do
        IO.puts("   Answer: #{sample.answer}")
      end
    end

  {:error, reason} ->
    IO.puts("   Could not load: #{inspect(reason)}")
    IO.puts("   (Dataset may need HF authentication or download)")
    IO.puts("")
    IO.puts("   To download datasets, ensure HF_TOKEN is set:")
    IO.puts("   export HF_TOKEN=hf_xxxxxxxxxxxxx")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 8. Dataset Size Information
# -----------------------------------------------------------------------------

IO.puts("8. Dataset Sizes by Split:")
for name <- [:medqa, :pubmedqa, :medmcqa] do
  case Config.get(name) do
    {:ok, config} ->
      IO.puts("   #{name}:")
      for {split, size} <- config.size do
        IO.puts("     #{split}: #{size} samples")
      end
    _ -> :ok
  end
end
IO.puts("")

# -----------------------------------------------------------------------------
# 9. Streaming Configuration for Large Datasets
# -----------------------------------------------------------------------------

IO.puts("9. Large Dataset Configuration (ReasonMed):")
case Config.get(:reasonmed) do
  {:ok, config} ->
    IO.puts("   Name: #{config.name}")
    IO.puts("   Size: #{config.size[:train]} samples")
    IO.puts("   Streaming: #{config.streaming} (REQUIRED for this dataset)")
    IO.puts("")
    IO.puts("   Example usage:")
    IO.puts("     {:ok, stream} = Datasets.load(:reasonmed,")
    IO.puts("       streaming: true,")
    IO.puts("       limit: 10_000")
    IO.puts("     )")
  {:error, reason} ->
    IO.puts("   Error: #{inspect(reason)}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 10. MMLU Medical Subjects
# -----------------------------------------------------------------------------

IO.puts("10. MMLU Medical Subjects:")
case Config.get(:mmlu_medical) do
  {:ok, config} ->
    subjects = config[:medical_subjects] || []
    for subject <- subjects do
      IO.puts("    - #{subject}")
    end
  {:error, reason} ->
    IO.puts("   Error: #{inspect(reason)}")
end
IO.puts("")

IO.puts("=== Dataset Examples Complete ===")
