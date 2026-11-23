#!/usr/bin/env elixir
# Example 09: Multi-Model Medical Chat Comparison
#
# This example demonstrates REAL inference across multiple medical LLMs:
# - Queries the same medical question to multiple models
# - Measures actual inference time per model
# - Compares response quality across models
#
# Prerequisites:
#   ollama pull nomic-embed-text
#   ollama pull hf.co/BioMistral/BioMistral-7B-GGUF
#   ollama pull medllama2
#   ollama pull meditron:7b
#
# Run: mix run examples/09_multi_model_chat.exs

# Debug mode: set DEBUG=1 to see verbose output
debug_mode = System.get_env("DEBUG") == "1"

if debug_mode do
  Logger.configure(level: :debug)
  IO.puts("[DEBUG MODE ENABLED]")
else
  Logger.configure(level: :warning)
end

IO.puts("""

================================================================================
  Example 09: Multi-Model Medical Chat Comparison

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
# 2. Discover Available Medical Models
# ==============================================================================
IO.puts("\n\n2. DISCOVERING AVAILABLE MODELS")
IO.puts(String.duplicate("-", 70))

{:ok, all_models} = MedlumLlm.list_models()

# Helper to check if model is loaded in VRAM
get_loaded_models = fn ->
  case System.cmd("ollama", ["ps"], stderr_to_stdout: true) do
    {output, 0} ->
      output
      |> String.split("\n")
      |> Enum.drop(1)  # Skip header
      |> Enum.map(fn line ->
        case String.split(line, ~r/\s+/, parts: 2) do
          [name | _] -> name
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    _ -> []
  end
end

# Define medical models we want to compare
# NOTE: Prefer native ollama models (e.g., meditron:7b) over raw GGUFs (TheBloke)
# because native models have stop tokens configured. Raw GGUFs may generate forever.
medical_model_patterns = [
  {"BioMistral-7B", ~r/biomistral/i},
  {"MedLLaMA2", ~r/medllama2/i},
  {"Meditron-7B", ~r/^meditron:7b$/i},  # Prefer native, not TheBloke GGUF
  {"OpenBioLLM-8B", ~r/openbio.*8b/i},
  {"Llama-3.2", ~r/llama.*3\.2/i}
]

available_models =
  Enum.reduce(medical_model_patterns, [], fn {name, pattern}, acc ->
    case Enum.find(all_models, fn %{"name" => model_name} ->
           String.match?(model_name, pattern)
         end) do
      nil -> acc
      %{"name" => model_name} -> [{name, model_name} | acc]
    end
  end)
  |> Enum.reverse()

IO.puts("\n  Medical models available locally:\n")

if Enum.empty?(available_models) do
  IO.puts("  WARNING: No medical models found!")
  IO.puts("  Please pull at least one model:")
  IO.puts("    ollama pull hf.co/BioMistral/BioMistral-7B-GGUF")
  IO.puts("    ollama pull medllama2")
  IO.puts("    ollama pull meditron:7b")
  System.halt(1)
else
  Enum.each(available_models, fn {display_name, actual_name} ->
    IO.puts("    #{display_name}: #{actual_name}")
  end)
end

# ==============================================================================
# 3. Medical Question for Comparison
# ==============================================================================
IO.puts("\n\n3. MEDICAL QUERY FOR COMPARISON")
IO.puts(String.duplicate("-", 70))

medical_question = """
A 58-year-old male presents with sudden onset chest pain radiating to the left arm,
diaphoresis, and shortness of breath. ECG shows ST-elevation in leads V1-V4.
Troponin I is 2.8 ng/mL (normal <0.04).

What is the most likely diagnosis and what immediate interventions are indicated?
"""

IO.puts("\n  Query:")
IO.puts("  " <> String.replace(medical_question, "\n", "\n  "))

# ==============================================================================
# 4. Query Each Model
# ==============================================================================
IO.puts("\n\n4. QUERYING EACH MODEL (REAL INFERENCE)")
IO.puts(String.duplicate("-", 70))

# Check what's currently loaded
loaded_models = get_loaded_models.()

IO.puts("\n  Currently loaded in VRAM:")
if Enum.empty?(loaded_models) do
  IO.puts("    (none)")
else
  Enum.each(loaded_models, fn m -> IO.puts("    - #{m}") end)
end

results =
  Enum.map(available_models, fn {display_name, model_name} ->
    IO.puts("\n  ─────────────────────────────────────────────────────────")
    IO.puts("  Model: #{display_name}")
    IO.puts("  Ollama name: #{model_name}")

    # Check if model is already in VRAM
    is_loaded = Enum.any?(loaded_models, fn m -> String.starts_with?(model_name, m) or String.starts_with?(m, model_name) end)

    if is_loaded do
      IO.puts("  Status: WARM (already in VRAM)")
    else
      IO.puts("  Status: COLD (will load into VRAM)")
    end

    IO.puts("  Sending query...")

    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        # 180 second timeout, max 500 tokens to prevent infinite generation
        # (some models like raw GGUFs may lack stop tokens)
        case MedlumLlm.chat(medical_question,
               model: model_name,
               system: "You are a clinical assistant. Provide a concise differential diagnosis.",
               timeout: 180_000,
               max_tokens: 500
             ) do
          {:ok, response} ->
            elapsed = System.monotonic_time(:millisecond) - start_time
            {:ok, response, elapsed}

          {:error, reason} ->
            elapsed = System.monotonic_time(:millisecond) - start_time
            {:error, reason, elapsed}
        end
      rescue
        e ->
          elapsed = System.monotonic_time(:millisecond) - start_time
          {:error, Exception.message(e), elapsed}
      end

    case result do
      {:ok, response, elapsed} ->
        IO.puts("  Result: SUCCESS")
        IO.puts("  Time: #{elapsed}ms (#{Float.round(elapsed / 1000, 1)}s)")
        IO.puts("  Response length: #{String.length(response)} chars")
        IO.puts("  Preview: #{String.slice(response, 0, 80)}...")
        {display_name, model_name, :ok, response, elapsed}

      {:error, reason, elapsed} ->
        IO.puts("  Result: FAILED")
        IO.puts("  Time: #{elapsed}ms (#{Float.round(elapsed / 1000, 1)}s)")
        IO.puts("  Error: #{inspect(reason)}")
        {display_name, model_name, :error, reason, elapsed}
    end

    # Update loaded models list after each query (model may have been swapped)
  end)

# ==============================================================================
# 5. Compare Results
# ==============================================================================
IO.puts("\n\n5. COMPARISON SUMMARY")
IO.puts(String.duplicate("-", 70))

successful = Enum.filter(results, fn {_, _, status, _, _} -> status == :ok end)
failed = Enum.filter(results, fn {_, _, status, _, _} -> status == :error end)

IO.puts("\n  Successful: #{length(successful)} / #{length(results)}")

if length(successful) > 0 do
  IO.puts("\n  Performance Ranking (by response time):\n")

  successful
  |> Enum.sort_by(fn {_, _, _, _, elapsed} -> elapsed end)
  |> Enum.with_index(1)
  |> Enum.each(fn {{display_name, _, _, _, elapsed}, rank} ->
    IO.puts("    #{rank}. #{display_name}: #{elapsed}ms")
  end)
end

if length(failed) > 0 do
  IO.puts("\n  Failed models:")

  Enum.each(failed, fn {display_name, _, _, reason, _} ->
    IO.puts("    - #{display_name}: #{inspect(reason)}")
  end)
end

# ==============================================================================
# 6. Full Responses
# ==============================================================================
if length(successful) > 0 do
  IO.puts("\n\n6. FULL RESPONSES")
  IO.puts(String.duplicate("-", 70))

  Enum.each(successful, fn {display_name, model_name, _, response, elapsed} ->
    IO.puts("\n  ┌─ #{display_name} (#{elapsed}ms)")
    IO.puts("  │  Model: #{model_name}")
    IO.puts("  │")

    response
    |> String.split("\n")
    |> Enum.take(20)
    |> Enum.each(fn line ->
      IO.puts("  │  #{line}")
    end)

    if String.length(response) > 1000 do
      IO.puts("  │  [Response truncated...]")
    end

    IO.puts("  └" <> String.duplicate("─", 60))
  end)
end

# Exit with error if any models failed
if length(failed) > 0 do
  IO.puts("""

  ================================================================================
    Example FAILED - #{length(failed)} model(s) did not respond

    Failed models: #{Enum.map_join(failed, ", ", fn {name, _, _, _, _} -> name end)}
  ================================================================================
  """)
  System.halt(1)
else
  IO.puts("""

  ================================================================================
    Example Complete - Multi-Model Medical Chat

    Key Observations:
    - All responses came from REAL model inference
    - Response times reflect actual GPU computation
    - Different models have different response characteristics
    - Medical models are optimized for clinical terminology
  ================================================================================
  """)
end
