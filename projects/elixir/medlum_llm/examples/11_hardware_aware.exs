#!/usr/bin/env elixir
# Example 11: Hardware-Aware Model Selection
#
# This example demonstrates REAL model discovery and hardware-aware selection:
# - Queries Ollama for all available models
# - Shows model sizes and VRAM requirements
# - Demonstrates tiered model selection based on task
# - Runs inference on appropriate models for your hardware
#
# Prerequisites:
#   ollama pull nomic-embed-text
#   ollama pull hf.co/BioMistral/BioMistral-7B-GGUF
#   ollama pull medllama2  # Optional
#   ollama pull meditron:7b  # Optional
#
# Run: mix run examples/11_hardware_aware.exs

Logger.configure(level: :warning)

IO.puts("""

================================================================================
  Example 11: Hardware-Aware Model Selection

  This example uses REAL models - no mocks or simulations!
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
# 2. Full Model Inventory
# ==============================================================================
IO.puts("\n\n2. LOCAL MODEL INVENTORY")
IO.puts(String.duplicate("-", 70))

{:ok, all_models} = MedlumLlm.list_models()

IO.puts("\n  Found #{length(all_models)} models locally:\n")

# Sort by size
sorted_models =
  all_models
  |> Enum.sort_by(fn %{"size" => size} -> size end)
  |> Enum.map(fn model ->
    name = model["name"]
    size_bytes = model["size"]
    size_gb = Float.round(size_bytes / 1_000_000_000, 2)

    details = model["details"] || %{}
    param_size = details["parameter_size"] || "unknown"
    family = details["family"] || "unknown"
    quant = details["quantization_level"] || "unknown"

    %{
      name: name,
      size_gb: size_gb,
      param_size: param_size,
      family: family,
      quant: quant
    }
  end)

IO.puts("  Model                                          | Size (GB) | Parameters | Family")
IO.puts("  " <> String.duplicate("-", 85))

Enum.each(sorted_models, fn model ->
  name = String.slice(model.name, 0, 45) |> String.pad_trailing(45)
  size = Float.to_string(model.size_gb) |> String.pad_leading(8)
  params = String.pad_trailing(model.param_size, 10)
  family = model.family

  IO.puts("  #{name} | #{size} | #{params} | #{family}")
end)

# ==============================================================================
# 3. Categorize by Size Tier
# ==============================================================================
IO.puts("\n\n3. MODELS BY SIZE TIER")
IO.puts(String.duplicate("-", 70))

small_models = Enum.filter(sorted_models, fn m -> m.size_gb < 2.0 end)
medium_models = Enum.filter(sorted_models, fn m -> m.size_gb >= 2.0 and m.size_gb < 6.0 end)
large_models = Enum.filter(sorted_models, fn m -> m.size_gb >= 6.0 and m.size_gb < 20.0 end)
xlarge_models = Enum.filter(sorted_models, fn m -> m.size_gb >= 20.0 end)

IO.puts("\n  SMALL (< 2GB VRAM) - Fastest inference:")
if Enum.empty?(small_models) do
  IO.puts("    (none)")
else
  Enum.each(small_models, fn m ->
    IO.puts("    - #{m.name} (#{m.size_gb}GB)")
  end)
end

IO.puts("\n  MEDIUM (2-6GB VRAM) - Good for 7B models:")
if Enum.empty?(medium_models) do
  IO.puts("    (none)")
else
  Enum.each(medium_models, fn m ->
    IO.puts("    - #{m.name} (#{m.size_gb}GB)")
  end)
end

IO.puts("\n  LARGE (6-20GB VRAM) - 13B+ models, fits RTX 4060/5060 Ti:")
if Enum.empty?(large_models) do
  IO.puts("    (none)")
else
  Enum.each(large_models, fn m ->
    IO.puts("    - #{m.name} (#{m.size_gb}GB)")
  end)
end

IO.puts("\n  X-LARGE (> 20GB) - Requires CPU offload or multi-GPU:")
if Enum.empty?(xlarge_models) do
  IO.puts("    (none)")
else
  Enum.each(xlarge_models, fn m ->
    IO.puts("    - #{m.name} (#{m.size_gb}GB) [WARNING: May need CPU offload]")
  end)
end

# ==============================================================================
# 4. Identify Medical Models
# ==============================================================================
IO.puts("\n\n4. MEDICAL-SPECIFIC MODELS")
IO.puts(String.duplicate("-", 70))

medical_keywords = ["biomistral", "medllama", "meditron", "openbio", "med", "clinical", "health"]

medical_models =
  Enum.filter(sorted_models, fn model ->
    lower_name = String.downcase(model.name)
    Enum.any?(medical_keywords, fn kw -> String.contains?(lower_name, kw) end)
  end)

IO.puts("\n  Models with medical training:\n")

if Enum.empty?(medical_models) do
  IO.puts("    No medical models found locally.")
  IO.puts("    Consider pulling: ollama pull hf.co/BioMistral/BioMistral-7B-GGUF")
else
  Enum.each(medical_models, fn m ->
    IO.puts("    - #{m.name}")
    IO.puts("      Size: #{m.size_gb}GB, Parameters: #{m.param_size}")
  end)
end

# ==============================================================================
# 5. Hardware-Aware Model Selection Demo
# ==============================================================================
IO.puts("\n\n5. HARDWARE-AWARE MODEL SELECTION")
IO.puts(String.duplicate("-", 70))

# Define task requirements
tasks = [
  %{
    name: "Quick Medical Q&A",
    description: "Fast response needed, accuracy less critical",
    max_vram: 4.0,
    prefer_medical: true
  },
  %{
    name: "Clinical Documentation",
    description: "Quality important, moderate speed",
    max_vram: 8.0,
    prefer_medical: true
  },
  %{
    name: "Critical Diagnosis Support",
    description: "Highest accuracy needed, speed less important",
    max_vram: 16.0,
    prefer_medical: true
  }
]

Enum.each(tasks, fn task ->
  IO.puts("\n  Task: #{task.name}")
  IO.puts("  Requirements: Max #{task.max_vram}GB VRAM, Medical preferred: #{task.prefer_medical}")

  # Select best model for task
  candidates =
    sorted_models
    |> Enum.filter(fn m -> m.size_gb <= task.max_vram end)

  # Prefer medical models if requested
  selected =
    if task.prefer_medical do
      medical_candidate =
        Enum.find(Enum.reverse(candidates), fn m ->
          lower = String.downcase(m.name)
          Enum.any?(medical_keywords, fn kw -> String.contains?(lower, kw) end)
        end)

      medical_candidate || List.last(candidates)
    else
      List.last(candidates)
    end

  if selected do
    IO.puts("  Selected: #{selected.name} (#{selected.size_gb}GB)")
  else
    IO.puts("  WARNING: No suitable model found!")
  end
end)

# ==============================================================================
# 6. Run Inference on Selected Model
# ==============================================================================
IO.puts("\n\n6. INFERENCE ON BEST AVAILABLE MODEL")
IO.puts(String.duplicate("-", 70))

# Find best medical model under 8GB
best_model =
  sorted_models
  |> Enum.filter(fn m -> m.size_gb <= 8.0 end)
  |> Enum.filter(fn m ->
    lower = String.downcase(m.name)
    Enum.any?(medical_keywords, fn kw -> String.contains?(lower, kw) end)
  end)
  |> List.last()

# Fallback to any model under 8GB if no medical model
best_model = best_model || (sorted_models |> Enum.filter(fn m -> m.size_gb <= 8.0 end) |> List.last())

if best_model do
  IO.puts("\n  Using: #{best_model.name} (#{best_model.size_gb}GB)")

  medical_question = "What are the typical symptoms of acute myocardial infarction?"
  IO.puts("  Query: #{medical_question}")

  start_time = System.monotonic_time(:millisecond)

  case MedlumLlm.chat(medical_question, model: best_model.name, timeout: 60_000) do
    {:ok, response} ->
      elapsed = System.monotonic_time(:millisecond) - start_time
      IO.puts("\n  Response (#{elapsed}ms):")
      IO.puts("  " <> String.replace(String.slice(response, 0, 500), "\n", "\n  "))

      if String.length(response) > 500 do
        IO.puts("  [...]")
      end

    {:error, reason} ->
      IO.puts("\n  ERROR: #{inspect(reason)}")
  end
else
  IO.puts("\n  No suitable model available for inference demo.")
  IO.puts("  Please pull a model: ollama pull hf.co/BioMistral/BioMistral-7B-GGUF")
end

IO.puts("""

================================================================================
  Example Complete - Hardware-Aware Model Selection

  Key Observations:
  - Model sizes vary from < 1GB to 40GB+
  - 7B models (~4GB) fit comfortably on 16GB GPU
  - 13B models (~8GB) also fit on 16GB GPU
  - 70B models require CPU offload or 48GB+ GPU
  - Medical models provide domain-specific optimization
================================================================================
""")
