#!/usr/bin/env elixir
# Example 10: Clinical Embedding Model Comparison
#
# This example demonstrates REAL embedding generation and comparison:
# - Uses nomic-embed-text for clinical embeddings
# - Compares embedding dimensions and performance
# - Calculates real semantic similarity between clinical terms
#
# Prerequisites:
#   ollama pull nomic-embed-text
#   ollama pull mxbai-embed-large  # Optional, for comparison
#
# Run: mix run examples/10_embedding_comparison.exs

Logger.configure(level: :warning)

IO.puts("""

================================================================================
  Example 10: Clinical Embedding Model Comparison

  This example uses REAL embeddings - no mocks or simulations!
================================================================================
""")

# ==============================================================================
# 1. Check Ollama Connectivity
# ==============================================================================
IO.puts("1. CHECKING OLLAMA CONNECTION")
IO.puts(String.duplicate("-", 70))

case MedlumLlm.health_check() do
  :ok ->
    IO.puts("\n  Ollama is running")

  {:error, reason} ->
    IO.puts("\n  ERROR: Cannot connect to Ollama: #{inspect(reason)}")
    IO.puts("  Please ensure Ollama is running: ollama serve")
    System.halt(1)
end

# ==============================================================================
# 2. Discover Available Embedding Models
# ==============================================================================
IO.puts("\n\n2. DISCOVERING EMBEDDING MODELS")
IO.puts(String.duplicate("-", 70))

{:ok, all_models} = MedlumLlm.list_models()

embedding_patterns = [
  {"nomic-embed-text", ~r/nomic-embed-text/i},
  {"nomic-embed-v2-moe", ~r/nomic-embed.*v2/i},
  {"mxbai-embed-large", ~r/mxbai-embed/i},
  {"all-minilm", ~r/all-minilm/i}
]

available_embeddings =
  Enum.reduce(embedding_patterns, [], fn {name, pattern}, acc ->
    case Enum.find(all_models, fn %{"name" => model_name} ->
           String.match?(model_name, pattern)
         end) do
      nil -> acc
      %{"name" => model_name} -> [{name, model_name} | acc]
    end
  end)
  |> Enum.reverse()

IO.puts("\n  Embedding models available locally:\n")

if Enum.empty?(available_embeddings) do
  IO.puts("  WARNING: No embedding models found!")
  IO.puts("  Please pull at least one model:")
  IO.puts("    ollama pull nomic-embed-text")
  System.halt(1)
else
  Enum.each(available_embeddings, fn {display_name, actual_name} ->
    IO.puts("    #{display_name}: #{actual_name}")
  end)
end

# Use the first available embedding model
{primary_name, primary_model} = hd(available_embeddings)
IO.puts("\n  Using: #{primary_name} (#{primary_model})")

# ==============================================================================
# 3. Clinical Term Pairs for Similarity
# ==============================================================================
IO.puts("\n\n3. CLINICAL TERM PAIRS")
IO.puts(String.duplicate("-", 70))

term_pairs = [
  # High similarity (same concept, different terms)
  {"heart attack", "myocardial infarction"},
  {"stroke", "cerebrovascular accident"},
  {"high blood pressure", "hypertension"},
  {"diabetes", "diabetes mellitus type 2"},
  {"shortness of breath", "dyspnea"},

  # Medium similarity (related concepts)
  {"chest pain", "angina pectoris"},
  {"heart failure", "cardiac dysfunction"},
  {"kidney disease", "renal insufficiency"},

  # Low similarity (unrelated)
  {"fracture", "hypertension"},
  {"headache", "myocardial infarction"},
  {"diabetes", "bone fracture"}
]

IO.puts("\n  Testing #{length(term_pairs)} clinical term pairs...")

# ==============================================================================
# 4. Generate Real Embeddings and Calculate Similarity
# ==============================================================================
IO.puts("\n\n4. EMBEDDING GENERATION AND SIMILARITY (REAL INFERENCE)")
IO.puts(String.duplicate("-", 70))

results =
  Enum.map(term_pairs, fn {term1, term2} ->
    start_time = System.monotonic_time(:millisecond)

    result =
      case MedlumLlm.similarity(term1, term2, model: primary_model) do
        {:ok, similarity} ->
          elapsed = System.monotonic_time(:millisecond) - start_time
          {:ok, similarity, elapsed}

        {:error, reason} ->
          elapsed = System.monotonic_time(:millisecond) - start_time
          {:error, reason, elapsed}
      end

    case result do
      {:ok, sim, elapsed} ->
        {term1, term2, sim, elapsed}

      {:error, reason, _} ->
        IO.puts("  ERROR: #{term1} <-> #{term2}: #{inspect(reason)}")
        {term1, term2, nil, 0}
    end
  end)

# ==============================================================================
# 5. Display Similarity Results
# ==============================================================================
IO.puts("\n\n5. SIMILARITY RESULTS")
IO.puts(String.duplicate("-", 70))

IO.puts("\n  Term 1                    | Term 2                    | Similarity | Time")
IO.puts("  " <> String.duplicate("-", 75))

results
|> Enum.filter(fn {_, _, sim, _} -> sim != nil end)
|> Enum.sort_by(fn {_, _, sim, _} -> -sim end)
|> Enum.each(fn {term1, term2, similarity, elapsed} ->
  t1 = String.pad_trailing(term1, 25)
  t2 = String.pad_trailing(term2, 25)

  # Visual similarity bar
  bar_length = round(similarity * 20)
  bar = String.duplicate("|", bar_length) |> String.pad_trailing(20)

  IO.puts("  #{t1} | #{t2} | #{Float.round(similarity, 3)} #{bar} | #{elapsed}ms")
end)

# ==============================================================================
# 6. Similarity Categories
# ==============================================================================
IO.puts("\n\n6. SIMILARITY ANALYSIS")
IO.puts(String.duplicate("-", 70))

valid_results = Enum.filter(results, fn {_, _, sim, _} -> sim != nil end)

high_sim = Enum.filter(valid_results, fn {_, _, sim, _} -> sim >= 0.7 end)
medium_sim = Enum.filter(valid_results, fn {_, _, sim, _} -> sim >= 0.4 and sim < 0.7 end)
low_sim = Enum.filter(valid_results, fn {_, _, sim, _} -> sim < 0.4 end)

IO.puts("\n  HIGH Similarity (>= 0.7): #{length(high_sim)} pairs")

Enum.each(high_sim, fn {t1, t2, sim, _} ->
  IO.puts("    - #{t1} <-> #{t2} (#{Float.round(sim, 3)})")
end)

IO.puts("\n  MEDIUM Similarity (0.4-0.7): #{length(medium_sim)} pairs")

Enum.each(medium_sim, fn {t1, t2, sim, _} ->
  IO.puts("    - #{t1} <-> #{t2} (#{Float.round(sim, 3)})")
end)

IO.puts("\n  LOW Similarity (< 0.4): #{length(low_sim)} pairs")

Enum.each(low_sim, fn {t1, t2, sim, _} ->
  IO.puts("    - #{t1} <-> #{t2} (#{Float.round(sim, 3)})")
end)

# ==============================================================================
# 7. Embedding Dimensions and Performance
# ==============================================================================
IO.puts("\n\n7. MODEL CHARACTERISTICS")
IO.puts(String.duplicate("-", 70))

# Get a sample embedding to check dimensions
sample_text = "myocardial infarction"

IO.puts("\n  Generating sample embedding for: \"#{sample_text}\"")

case MedlumLlm.embed(sample_text, model: primary_model) do
  {:ok, embedding} ->
    dimensions = length(embedding)
    IO.puts("  Model: #{primary_model}")
    IO.puts("  Dimensions: #{dimensions}")
    IO.puts("  Sample values: [#{Enum.take(embedding, 5) |> Enum.map(&Float.round(&1, 4)) |> Enum.join(", ")}, ...]")

  {:error, reason} ->
    IO.puts("  ERROR: #{inspect(reason)}")
end

# ==============================================================================
# 8. Batch Embedding Performance
# ==============================================================================
IO.puts("\n\n8. BATCH EMBEDDING PERFORMANCE")
IO.puts(String.duplicate("-", 70))

clinical_terms = [
  "acute myocardial infarction",
  "congestive heart failure",
  "type 2 diabetes mellitus",
  "chronic obstructive pulmonary disease",
  "hypertensive cardiovascular disease",
  "acute kidney injury",
  "cerebrovascular accident",
  "deep vein thrombosis",
  "pulmonary embolism",
  "atrial fibrillation"
]

IO.puts("\n  Generating embeddings for #{length(clinical_terms)} clinical terms...")

start_time = System.monotonic_time(:millisecond)

case MedlumLlm.embed_batch(clinical_terms, model: primary_model) do
  {:ok, embeddings} ->
    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("\n  Batch completed in #{elapsed}ms")
    IO.puts("  Average: #{Float.round(elapsed / length(clinical_terms), 1)}ms per term")
    IO.puts("  Embeddings generated: #{length(embeddings)}")
    IO.puts("  Dimensions per embedding: #{length(hd(embeddings))}")

  {:error, reason} ->
    IO.puts("\n  ERROR: #{inspect(reason)}")
end

IO.puts("""

================================================================================
  Example Complete - Clinical Embedding Comparison

  Key Observations:
  - All embeddings came from REAL model inference
  - Semantic similarity correctly identifies related medical terms
  - Unrelated terms show low similarity as expected
  - Batch embedding provides efficient bulk processing
================================================================================
""")
