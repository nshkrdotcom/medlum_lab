#!/usr/bin/env elixir
# Example 05: Chat with Meditron-7B
#
# This example demonstrates Meditron-7B:
# - Evidence-based medicine queries
# - Medical literature understanding
# - Clinical guidelines interpretation
#
# Requires: ollama pull hf.co/TheBloke/meditron-7B-GGUF
#
# Run: mix run examples/05_chat_meditron.exs

Logger.configure(level: :warning)

IO.puts("""

================================================================================
  Example 05: Chat with Meditron-7B
================================================================================

Model: Meditron-7B (trained on medical literature and guidelines)
VRAM: ~4GB (Q4_K_M quantization)
Strengths: Evidence-based medicine, clinical guidelines
""")

# Check connection and model availability
case MedlumLlm.health_check() do
  :ok -> :ok
  {:error, _} ->
    IO.puts("ERROR: Cannot connect to Ollama.")
    System.halt(1)
end

case MedlumLlm.model_info(:meditron_7b) do
  {:ok, _} ->
    IO.puts("Model ready!\n")

  {:error, _} ->
    IO.puts("""
    ERROR: Meditron-7B not found.

    Pull it with:
      ollama pull hf.co/TheBloke/meditron-7B-GGUF

    """)
    System.halt(1)
end

# -----------------------------------------------------------------------------
# 1. Evidence-Based Medicine Query
# -----------------------------------------------------------------------------
IO.puts("1. Evidence-Based Medicine Query")
IO.puts(String.duplicate("-", 60))

ebm_query = """
What is the evidence for using statins for primary prevention of cardiovascular
disease in patients without established heart disease but with risk factors?
"""

IO.puts("Query: #{String.slice(ebm_query, 0, 80)}...\n")

case MedlumLlm.chat(ebm_query,
       model: :meditron_7b,
       max_tokens: 300,
       system: "You are an evidence-based medicine expert. Reference clinical trials and guidelines when possible."
     ) do
  {:ok, response} ->
    IO.puts("Response:\n#{response}")

  {:error, reason} ->
    IO.puts("[ERROR] #{inspect(reason)}")
end

# -----------------------------------------------------------------------------
# 2. Treatment Guideline Summary
# -----------------------------------------------------------------------------
IO.puts("\n\n2. Treatment Guideline Summary")
IO.puts(String.duplicate("-", 60))

guideline_query = """
Summarize the current treatment approach for community-acquired pneumonia
in hospitalized adults, including antibiotic selection and duration.
"""

IO.puts("Query: #{String.slice(guideline_query, 0, 80)}...\n")

case MedlumLlm.chat(guideline_query, model: :meditron_7b, max_tokens: 300) do
  {:ok, response} ->
    IO.puts("Response:\n#{response}")

  {:error, reason} ->
    IO.puts("[ERROR] #{inspect(reason)}")
end

# -----------------------------------------------------------------------------
# 3. Medical Concept Explanation
# -----------------------------------------------------------------------------
IO.puts("\n\n3. Medical Concept Explanation")
IO.puts(String.duplicate("-", 60))

concept_query = """
Explain the renin-angiotensin-aldosterone system (RAAS) and how ACE inhibitors
and ARBs work to treat hypertension and heart failure.
"""

IO.puts("Query: #{String.slice(concept_query, 0, 80)}...\n")

case MedlumLlm.chat(concept_query, model: :meditron_7b, max_tokens: 300) do
  {:ok, response} ->
    IO.puts("Response:\n#{response}")

  {:error, reason} ->
    IO.puts("[ERROR] #{inspect(reason)}")
end

# -----------------------------------------------------------------------------
# 4. Screening Recommendations
# -----------------------------------------------------------------------------
IO.puts("\n\n4. Screening Recommendations")
IO.puts(String.duplicate("-", 60))

screening_query = """
What are the current recommendations for colorectal cancer screening?
Include age to start, frequency, and available screening methods.
"""

IO.puts("Query: #{String.slice(screening_query, 0, 80)}...\n")

case MedlumLlm.chat(screening_query, model: :meditron_7b, max_tokens: 250) do
  {:ok, response} ->
    IO.puts("Response:\n#{response}")

  {:error, reason} ->
    IO.puts("[ERROR] #{inspect(reason)}")
end

IO.puts("""


================================================================================
  Example Complete
================================================================================
""")
