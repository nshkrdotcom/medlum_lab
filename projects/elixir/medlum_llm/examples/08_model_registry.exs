#!/usr/bin/env elixir
# Example 08: Model Registry - Exploring the Model Catalog
#
# This example demonstrates the enhanced Model Registry with:
# - Hierarchical model organization (category, tier, domain)
# - Hardware-aware model selection
# - Task-based model recommendations
#
# Run: mix run examples/08_model_registry.exs

Logger.configure(level: :warning)

alias MedlumLlm.Models.Registry

IO.puts("""

================================================================================
  Example 08: Model Registry - Exploring the Model Catalog
================================================================================
""")

# ==============================================================================
# 1. Model Categories
# ==============================================================================
IO.puts("1. MODELS BY CATEGORY")
IO.puts(String.duplicate("-", 70))

categories = [:chat, :embed, :ner, :pii]

Enum.each(categories, fn category ->
  models = Registry.by_category(category)
  IO.puts("\n  #{String.upcase(to_string(category))} Models (#{length(models)}):")

  Enum.each(models, fn model ->
    tier_badge = "[#{model.tier}]" |> String.pad_trailing(10)
    vram = "#{model.vram_gb}GB"
    IO.puts("    #{tier_badge} #{model.name} (#{vram})")
  end)
end)

# ==============================================================================
# 2. NER Models by Domain
# ==============================================================================
IO.puts("\n\n2. NER MODELS BY DOMAIN")
IO.puts(String.duplicate("-", 70))

domains = [:disease, :pharma, :chemical, :anatomy]

Enum.each(domains, fn domain ->
  models = Registry.by_category(:ner, domain: domain)
  IO.puts("\n  #{String.upcase(to_string(domain))} Domain:")

  Enum.each(models, fn model ->
    hf_repo = model.hf_repo || "N/A"
    IO.puts("    - #{model.name}")
    IO.puts("      HuggingFace: #{hf_repo}")
    IO.puts("      F1 Estimate: #{Map.get(model.medical_benchmarks, :f1, "N/A")}")
  end)
end)

# ==============================================================================
# 3. Models by Tier
# ==============================================================================
IO.puts("\n\n3. MODELS BY QUALITY TIER")
IO.puts(String.duplicate("-", 70))

tiers = [:fast, :balanced, :accurate]

Enum.each(tiers, fn tier ->
  models = Registry.by_tier(tier)
  IO.puts("\n  #{String.upcase(to_string(tier))} Tier (#{length(models)} models):")

  models
  |> Enum.group_by(& &1.category)
  |> Enum.each(fn {category, cat_models} ->
    names = Enum.map(cat_models, & &1.name) |> Enum.join(", ")
    IO.puts("    #{category}: #{names}")
  end)
end)

# ==============================================================================
# 4. Hardware-Constrained Selection
# ==============================================================================
IO.puts("\n\n4. HARDWARE-CONSTRAINED MODEL SELECTION")
IO.puts(String.duplicate("-", 70))

vram_budgets = [4, 8, 16, 48]

Enum.each(vram_budgets, fn vram_gb ->
  models = Registry.fits_vram(vram_gb)
  IO.puts("\n  Models fitting #{vram_gb}GB VRAM (#{length(models)}):")

  models
  |> Enum.group_by(& &1.category)
  |> Enum.each(fn {category, cat_models} ->
    count = length(cat_models)
    IO.puts("    #{category}: #{count} models")
  end)
end)

# ==============================================================================
# 5. Hybrid Inference Models
# ==============================================================================
IO.puts("\n\n5. MODELS SUPPORTING HYBRID CPU+GPU INFERENCE")
IO.puts(String.duplicate("-", 70))

hybrid_models = Registry.supports_hybrid()
IO.puts("\n  These 70B models can use CPU+GPU hybrid inference:")

Enum.each(hybrid_models, fn model ->
  IO.puts("    - #{model.name}")
  IO.puts("      Parameters: #{model.params_b}B")
  IO.puts("      VRAM: #{model.vram_gb}GB (full), ~14-16GB (hybrid with 96GB RAM)")
  IO.puts("      Ollama: #{model.ollama_name}")
end)

# ==============================================================================
# 6. Task-Based Recommendations
# ==============================================================================
IO.puts("\n\n6. TASK-BASED MODEL RECOMMENDATIONS")
IO.puts(String.duplicate("-", 70))

tasks = [
  {:summarization, "General document summarization"},
  {:critical_analysis, "Clinical decision support"},
  {:medication_extraction, "Extract medications from notes"},
  {:disease_extraction, "Extract diagnoses from notes"},
  {:pii_detection, "HIPAA de-identification"},
  {:document_search, "Semantic search over corpus"}
]

Enum.each(tasks, fn {task, description} ->
  case Registry.recommend(task) do
    {:ok, model} ->
      IO.puts("\n  Task: #{task}")
      IO.puts("  Description: #{description}")
      IO.puts("  Recommended: #{model.name}")
      IO.puts("  Category: #{model.category}, Tier: #{model.tier}")
      IO.puts("  Provider: #{model.provider}")

    {:error, reason} ->
      IO.puts("\n  Task: #{task} - Error: #{reason}")
  end
end)

# ==============================================================================
# 7. Provider Distribution
# ==============================================================================
IO.puts("\n\n7. MODELS BY PROVIDER")
IO.puts(String.duplicate("-", 70))

providers = [:ollama, :huggingface]

Enum.each(providers, fn provider ->
  models = Registry.by_provider(provider)
  IO.puts("\n  #{String.upcase(to_string(provider))} Provider (#{length(models)} models):")

  models
  |> Enum.group_by(& &1.category)
  |> Enum.each(fn {category, cat_models} ->
    IO.puts("    #{category}:")
    Enum.each(cat_models, fn model ->
      IO.puts("      - #{model.id}")
    end)
  end)
end)

# ==============================================================================
# 8. Medical Benchmarks
# ==============================================================================
IO.puts("\n\n8. CHAT MODELS BY MEDICAL BENCHMARK PERFORMANCE")
IO.puts(String.duplicate("-", 70))

chat_models =
  Registry.by_category(:chat)
  |> Enum.filter(fn model -> Map.has_key?(model.medical_benchmarks, :medqa) end)
  |> Enum.sort_by(fn model -> model.medical_benchmarks.medqa end, :desc)

IO.puts("\n  Sorted by MedQA accuracy:")
Enum.each(chat_models, fn model ->
  accuracy = Float.round(model.medical_benchmarks.medqa * 100, 1)
  tier = "[#{model.tier}]" |> String.pad_trailing(10)
  IO.puts("    #{tier} #{model.name}: #{accuracy}%")
end)

IO.puts("""

================================================================================
  Example Complete - Model Registry Exploration

  Key Takeaways:
  - Registry organizes #{map_size(Registry.all())} models across 4 categories
  - Use by_category/1-2 to filter by category and domain
  - Use by_tier/1-2 to filter by quality tier
  - Use fits_vram/1 for hardware-constrained selection
  - Use recommend/1 for task-based model selection
  - Hybrid models (70B) can run on 16GB VRAM + 96GB RAM
================================================================================
""")
