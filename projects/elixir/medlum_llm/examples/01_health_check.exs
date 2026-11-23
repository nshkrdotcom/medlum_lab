#!/usr/bin/env elixir
# Example 01: Health Check and Model Discovery
#
# This example shows how to:
# - Check if Ollama is running
# - List available models
# - Get model information
#
# Run: mix run examples/01_health_check.exs

Logger.configure(level: :warning)

IO.puts("""

================================================================================
  Example 01: Health Check and Model Discovery
================================================================================
""")

# 1. Check if Ollama is running
IO.puts("1. Checking Ollama connection...")

case MedlumLlm.health_check() do
  :ok ->
    IO.puts("   [OK] Connected to Ollama at localhost:11434\n")

  {:error, reason} ->
    IO.puts("   [ERROR] Cannot connect: #{inspect(reason)}")
    IO.puts("   Make sure Ollama is running: ollama serve")
    System.halt(1)
end

# 2. List available models
IO.puts("2. Available models on this server:")

case MedlumLlm.list_models() do
  {:ok, models} when is_list(models) ->
    if Enum.empty?(models) do
      IO.puts("   No models found. Pull some models first:")
      IO.puts("   ollama pull nomic-embed-text")
      IO.puts("   ollama pull hf.co/BioMistral/BioMistral-7B-GGUF")
    else
      Enum.each(models, fn model ->
        name = model["name"] || model[:name] || "unknown"
        size = model["size"] || model[:size]
        size_str = if size, do: " (#{Float.round(size / 1_000_000_000, 2)} GB)", else: ""
        IO.puts("   - #{name}#{size_str}")
      end)
    end

  {:ok, response} ->
    IO.puts("   Response: #{inspect(response)}")

  {:error, reason} ->
    IO.puts("   [ERROR] #{inspect(reason)}")
end

# 3. Show supported medical models
IO.puts("\n3. MedlumLlm supported medical models:")
MedlumLlm.Models.print_summary()

# 4. Check if recommended models are available
IO.puts("\n4. Checking recommended models for 16GB GPU:")

recommended = [:biomistral_7b, :openbio_8b, :meditron_7b, :nomic_embed]

Enum.each(recommended, fn model_key ->
  {:ok, model_info} = MedlumLlm.Models.get(model_key)

  case MedlumLlm.model_info(model_key) do
    {:ok, _} ->
      IO.puts("   [READY] :#{model_key} - #{model_info.display_name}")

    {:error, _} ->
      IO.puts("   [NOT PULLED] :#{model_key} - #{model_info.display_name}")
      IO.puts("      Pull with: #{model_info.pull_command}")
  end
end)

IO.puts("""

================================================================================
  Example Complete
================================================================================
""")
