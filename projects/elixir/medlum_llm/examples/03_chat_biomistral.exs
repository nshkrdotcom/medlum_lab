#!/usr/bin/env elixir
# Example 03: Chat with BioMistral-7B
#
# This example demonstrates text generation with BioMistral-7B:
# - Simple medical Q&A
# - Multi-turn conversations
# - Custom system prompts
# - Clinical text completion
#
# Requires: ollama pull hf.co/BioMistral/BioMistral-7B-GGUF
#
# Run: mix run examples/03_chat_biomistral.exs

Logger.configure(level: :warning)

IO.puts("""

================================================================================
  Example 03: Chat with BioMistral-7B
================================================================================

Model: BioMistral-7B (medical domain fine-tuned Mistral)
VRAM: ~4GB (Q4_K_M quantization)
""")

# Check connection and model availability
case MedlumLlm.health_check() do
  :ok -> :ok
  {:error, _} ->
    IO.puts("ERROR: Cannot connect to Ollama. Make sure it's running.")
    System.halt(1)
end

case MedlumLlm.model_info(:biomistral_7b) do
  {:ok, _} ->
    IO.puts("Model ready!\n")

  {:error, _} ->
    IO.puts("""
    ERROR: BioMistral-7B not found.

    Pull it with:
      ollama pull hf.co/BioMistral/BioMistral-7B-GGUF

    """)
    System.halt(1)
end

# -----------------------------------------------------------------------------
# 1. Simple Medical Q&A
# -----------------------------------------------------------------------------
IO.puts("1. Simple Medical Q&A")
IO.puts(String.duplicate("-", 60))

questions = [
  "What are the main symptoms of type 2 diabetes?",
  "What is the difference between systolic and diastolic blood pressure?",
  "What are common side effects of metformin?"
]

Enum.each(questions, fn question ->
  IO.puts("\nQ: #{question}")
  IO.write("A: ")

  case MedlumLlm.chat(question, model: :biomistral_7b, max_tokens: 150) do
    {:ok, response} ->
      IO.puts(response)

    {:error, reason} ->
      IO.puts("[ERROR] #{inspect(reason)}")
  end
end)

IO.puts("")

# -----------------------------------------------------------------------------
# 2. Multi-turn Conversation
# -----------------------------------------------------------------------------
IO.puts("\n2. Multi-turn Conversation (Patient Case)")
IO.puts(String.duplicate("-", 60))

conversation = [
  %{
    role: "user",
    content: "A 55-year-old male presents with chest pain that started 2 hours ago. The pain radiates to his left arm. What should I consider?"
  },
  %{
    role: "assistant",
    content: "Given the presentation of chest pain radiating to the left arm in a 55-year-old male, acute coronary syndrome (ACS) should be high on your differential. This could include unstable angina, NSTEMI, or STEMI."
  },
  %{
    role: "user",
    content: "His ECG shows ST elevation in leads V1-V4. What is the diagnosis and immediate management?"
  }
]

IO.puts("\nConversation context:")
Enum.each(conversation, fn msg ->
  role = String.upcase(msg.role)
  IO.puts("#{role}: #{String.slice(msg.content, 0, 80)}...")
end)

IO.puts("\nModel response:")
case MedlumLlm.chat_messages(conversation, model: :biomistral_7b, max_tokens: 200) do
  {:ok, response} ->
    IO.puts(response)

  {:error, reason} ->
    IO.puts("[ERROR] #{inspect(reason)}")
end

# -----------------------------------------------------------------------------
# 3. Custom System Prompt (Specialist Persona)
# -----------------------------------------------------------------------------
IO.puts("\n\n3. Custom System Prompt (Cardiology Specialist)")
IO.puts(String.duplicate("-", 60))

cardiology_prompt = """
You are a board-certified cardiologist with 20 years of experience.
Provide detailed, evidence-based responses about cardiovascular conditions.
Include relevant diagnostic criteria and treatment guidelines when applicable.
"""

question = "Explain the pathophysiology of atrial fibrillation and its management."

IO.puts("System: #{String.slice(cardiology_prompt, 0, 60)}...")
IO.puts("Q: #{question}")
IO.write("\nA: ")

case MedlumLlm.chat(question,
       model: :biomistral_7b,
       system: cardiology_prompt,
       max_tokens: 250
     ) do
  {:ok, response} ->
    IO.puts(response)

  {:error, reason} ->
    IO.puts("[ERROR] #{inspect(reason)}")
end

# -----------------------------------------------------------------------------
# 4. Clinical Text Completion
# -----------------------------------------------------------------------------
IO.puts("\n\n4. Clinical Text Completion")
IO.puts(String.duplicate("-", 60))

clinical_prompts = [
  "Chief Complaint: 65-year-old female with shortness of breath\nHistory of Present Illness:",
  "Assessment: The patient presents with classic signs of",
  "Plan: Given the diagnosis of community-acquired pneumonia, we will"
]

Enum.each(clinical_prompts, fn prompt ->
  IO.puts("\nPrompt: #{String.slice(prompt, 0, 50)}...")
  IO.write("Completion: ")

  case MedlumLlm.Chat.complete(prompt, model: :biomistral_7b) do
    {:ok, completion} ->
      # Take first sentence/100 chars
      truncated = String.slice(completion, 0, 150)
      IO.puts(truncated <> "...")

    {:error, reason} ->
      IO.puts("[ERROR] #{inspect(reason)}")
  end
end)

IO.puts("""


================================================================================
  Example Complete
================================================================================
""")
