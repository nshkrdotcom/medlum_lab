#!/usr/bin/env elixir
# Example 07: Model Comparison
#
# This example compares responses from different medical LLMs
# on the same clinical query to help you choose the best model.
#
# Requires all models to be pulled for full comparison.
#
# Run: mix run examples/07_model_comparison.exs

Logger.configure(level: :warning)

IO.puts("""

================================================================================
  Example 07: Medical LLM Model Comparison
================================================================================

Comparing responses from different medical LLMs on the same query.
This helps you understand the strengths of each model.
""")

case MedlumLlm.health_check() do
  :ok -> :ok
  {:error, _} ->
    IO.puts("ERROR: Cannot connect to Ollama.")
    System.halt(1)
end

# Clinical query for comparison
query = """
A 50-year-old woman with type 2 diabetes presents with a painful, swollen right foot.
She has had poor glycemic control (HbA1c 10.2%). On examination, there is erythema,
warmth, and tenderness over the midfoot. What is the differential diagnosis and
recommended workup?
"""

models = [
  {:biomistral_7b, "BioMistral-7B", "Medical domain fine-tuned Mistral"},
  {:openbio_8b, "OpenBioLLM-8B", "Llama 3 based medical reasoning"},
  {:meditron_7b, "Meditron-7B", "Medical literature trained"}
]

IO.puts("Clinical Query:")
IO.puts(String.duplicate("-", 60))
IO.puts(query)
IO.puts(String.duplicate("-", 60))
IO.puts("")

# Check which models are available
available_models =
  Enum.filter(models, fn {key, _, _} ->
    case MedlumLlm.model_info(key) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end)

if Enum.empty?(available_models) do
  IO.puts("""
  No medical models found. Please pull at least one:

    ollama pull hf.co/BioMistral/BioMistral-7B-GGUF
    ollama pull hf.co/MoMonir/Llama3-OpenBioLLM-8B-GGUF
    ollama pull hf.co/TheBloke/meditron-7B-GGUF
  """)
  System.halt(1)
end

IO.puts("Available models: #{length(available_models)}/#{length(models)}\n")

# Query each model and collect responses
responses =
  Enum.map(available_models, fn {model_key, display_name, description} ->
    IO.puts("Querying #{display_name}...")

    start_time = System.monotonic_time(:millisecond)

    result =
      case MedlumLlm.chat(query, model: model_key, max_tokens: 300) do
        {:ok, response} -> {:ok, response}
        {:error, reason} -> {:error, reason}
      end

    elapsed = System.monotonic_time(:millisecond) - start_time

    {model_key, display_name, description, result, elapsed}
  end)

IO.puts("\n" <> String.duplicate("=", 70))
IO.puts("COMPARISON RESULTS")
IO.puts(String.duplicate("=", 70))

Enum.each(responses, fn {_key, display_name, description, result, elapsed} ->
  IO.puts("\n#{display_name}")
  IO.puts("#{description}")
  IO.puts("Response time: #{elapsed}ms")
  IO.puts(String.duplicate("-", 60))

  case result do
    {:ok, response} ->
      IO.puts(response)

    {:error, reason} ->
      IO.puts("[ERROR] #{inspect(reason)}")
  end

  IO.puts("")
end)

# Summary table
IO.puts(String.duplicate("=", 70))
IO.puts("SUMMARY")
IO.puts(String.duplicate("=", 70))
IO.puts("")
IO.puts("| Model                | Response Time | Status |")
IO.puts("|----------------------|---------------|--------|")

Enum.each(responses, fn {_key, display_name, _desc, result, elapsed} ->
  status = if match?({:ok, _}, result), do: "OK", else: "ERROR"
  time_str = "#{elapsed}ms" |> String.pad_leading(10)
  name_str = String.pad_trailing(display_name, 20)
  IO.puts("| #{name_str} | #{time_str}    | #{status}   |")
end)

IO.puts("""


Notes on model selection:
- BioMistral-7B: Good for general medical Q&A, balanced responses
- OpenBioLLM-8B: Strong clinical reasoning, differential diagnosis
- Meditron-7B: Evidence-focused, good for guideline-based queries

================================================================================
  Example Complete
================================================================================
""")
