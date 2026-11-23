#!/usr/bin/env elixir
# Example 04: Chat with OpenBioLLM-8B
#
# This example demonstrates OpenBioLLM-8B:
# - Medical reasoning and differential diagnosis
# - Clinical decision support
# - Evidence-based responses
#
# Requires: ollama pull hf.co/MoMonir/Llama3-OpenBioLLM-8B-GGUF
#
# Run: mix run examples/04_chat_openbio.exs

Logger.configure(level: :warning)

IO.puts("""

================================================================================
  Example 04: Chat with OpenBioLLM-8B
================================================================================

Model: OpenBioLLM-8B (Llama 3 based medical LLM)
VRAM: ~5GB (Q4_K_M quantization)
Strengths: Medical reasoning, differential diagnosis
""")

# Check connection and model availability
case MedlumLlm.health_check() do
  :ok -> :ok
  {:error, _} ->
    IO.puts("ERROR: Cannot connect to Ollama.")
    System.halt(1)
end

case MedlumLlm.model_info(:openbio_8b) do
  {:ok, _} ->
    IO.puts("Model ready!\n")

  {:error, _} ->
    IO.puts("""
    ERROR: OpenBioLLM-8B not found.

    Pull it with:
      ollama pull hf.co/MoMonir/Llama3-OpenBioLLM-8B-GGUF

    """)
    System.halt(1)
end

# -----------------------------------------------------------------------------
# 1. Differential Diagnosis
# -----------------------------------------------------------------------------
IO.puts("1. Differential Diagnosis")
IO.puts(String.duplicate("-", 60))

case_presentation = """
A 45-year-old woman presents with fatigue, weight gain, cold intolerance,
and constipation over the past 3 months. She also reports dry skin and
hair loss. Her heart rate is 58 bpm.

What is the differential diagnosis and what tests would you order?
"""

IO.puts("Case: #{String.slice(case_presentation, 0, 100)}...\n")

case MedlumLlm.chat(case_presentation, model: :openbio_8b, max_tokens: 300) do
  {:ok, response} ->
    IO.puts("Response:\n#{response}")

  {:error, reason} ->
    IO.puts("[ERROR] #{inspect(reason)}")
end

# -----------------------------------------------------------------------------
# 2. Drug Interaction Query
# -----------------------------------------------------------------------------
IO.puts("\n\n2. Drug Interaction Analysis")
IO.puts(String.duplicate("-", 60))

drug_query = """
A patient is taking warfarin for atrial fibrillation. They want to start
taking aspirin for pain relief. What are the risks and considerations?
"""

IO.puts("Query: #{String.slice(drug_query, 0, 80)}...\n")

case MedlumLlm.chat(drug_query, model: :openbio_8b, max_tokens: 250) do
  {:ok, response} ->
    IO.puts("Response:\n#{response}")

  {:error, reason} ->
    IO.puts("[ERROR] #{inspect(reason)}")
end

# -----------------------------------------------------------------------------
# 3. Clinical Guidelines Interpretation
# -----------------------------------------------------------------------------
IO.puts("\n\n3. Clinical Guidelines")
IO.puts(String.duplicate("-", 60))

guideline_query = """
According to current guidelines, what is the recommended target blood pressure
for a patient with diabetes and hypertension? What first-line medications
are preferred?
"""

IO.puts("Query: #{String.slice(guideline_query, 0, 80)}...\n")

case MedlumLlm.chat(guideline_query,
       model: :openbio_8b,
       max_tokens: 250,
       system: "You are a clinical guidelines expert. Cite specific guideline recommendations when possible."
     ) do
  {:ok, response} ->
    IO.puts("Response:\n#{response}")

  {:error, reason} ->
    IO.puts("[ERROR] #{inspect(reason)}")
end

# -----------------------------------------------------------------------------
# 4. Lab Value Interpretation
# -----------------------------------------------------------------------------
IO.puts("\n\n4. Lab Value Interpretation")
IO.puts(String.duplicate("-", 60))

lab_query = """
Interpret these lab results for a 60-year-old male:
- Hemoglobin: 9.2 g/dL (normal: 13.5-17.5)
- MCV: 68 fL (normal: 80-100)
- Ferritin: 8 ng/mL (normal: 20-250)
- TIBC: 450 mcg/dL (normal: 250-370)

What type of anemia is this and what could be the cause?
"""

IO.puts("Query: Lab interpretation...\n")

case MedlumLlm.chat(lab_query, model: :openbio_8b, max_tokens: 250) do
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
