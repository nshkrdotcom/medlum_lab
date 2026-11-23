#!/usr/bin/env elixir
# Example 02: Clinical Text Embeddings
#
# This example demonstrates:
# - Generating embeddings for clinical text
# - Batch embedding multiple texts
# - Calculating semantic similarity
# - Finding similar documents
#
# Requires: ollama pull nomic-embed-text
#
# Run: mix run examples/02_embeddings.exs

Logger.configure(level: :warning)

IO.puts("""

================================================================================
  Example 02: Clinical Text Embeddings
================================================================================

Using model: nomic-embed-text (768 dimensions)
""")

# Check connection
case MedlumLlm.health_check() do
  :ok -> :ok
  {:error, _} ->
    IO.puts("ERROR: Cannot connect to Ollama. Make sure it's running.")
    System.halt(1)
end

# -----------------------------------------------------------------------------
# 1. Single Embedding
# -----------------------------------------------------------------------------
IO.puts("1. Single Embedding")
IO.puts(String.duplicate("-", 60))

clinical_text = "Patient presents with acute chest pain radiating to left arm"
IO.puts("   Text: \"#{clinical_text}\"")

{:ok, embedding} = MedlumLlm.embed(clinical_text)
IO.puts("   Dimensions: #{length(embedding)}")
IO.puts("   First 5 values: #{Enum.take(embedding, 5) |> Enum.map(&Float.round(&1, 4)) |> inspect()}")
IO.puts("")

# -----------------------------------------------------------------------------
# 2. Batch Embeddings
# -----------------------------------------------------------------------------
IO.puts("2. Batch Embeddings")
IO.puts(String.duplicate("-", 60))

clinical_notes = [
  "Myocardial infarction with ST elevation in leads V1-V4",
  "Type 2 diabetes mellitus with poor glycemic control",
  "COPD exacerbation with increased dyspnea",
  "Left knee ACL tear confirmed by MRI",
  "New onset seizure activity with temporal lobe focus"
]

IO.puts("   Processing #{length(clinical_notes)} clinical notes...")
{:ok, embeddings} = MedlumLlm.embed_batch(clinical_notes)

Enum.zip(clinical_notes, embeddings)
|> Enum.with_index(1)
|> Enum.each(fn {{note, emb}, i} ->
  truncated = String.slice(note, 0, 45) <> "..."
  IO.puts("   #{i}. #{truncated} -> #{length(emb)} dims")
end)

IO.puts("")

# -----------------------------------------------------------------------------
# 3. Semantic Similarity
# -----------------------------------------------------------------------------
IO.puts("3. Semantic Similarity Between Clinical Terms")
IO.puts(String.duplicate("-", 60))

term_pairs = [
  # Synonyms (should be HIGH)
  {"heart attack", "myocardial infarction"},
  {"high blood pressure", "hypertension"},
  {"stroke", "cerebrovascular accident"},

  # Related (should be MEDIUM)
  {"chest pain", "heart attack"},
  {"shortness of breath", "COPD"},
  {"headache", "migraine"},

  # Unrelated (should be LOW)
  {"heart attack", "broken leg"},
  {"diabetes", "concussion"},
  {"pneumonia", "knee surgery"}
]

IO.puts("   Calculating similarity scores...\n")

Enum.chunk_every(term_pairs, 3)
|> Enum.with_index()
|> Enum.each(fn {pairs, chunk_idx} ->
  category =
    case chunk_idx do
      0 -> "SYNONYMS (expected: HIGH)"
      1 -> "RELATED (expected: MEDIUM)"
      2 -> "UNRELATED (expected: LOW)"
    end

  IO.puts("   #{category}")

  Enum.each(pairs, fn {t1, t2} ->
    {:ok, sim} = MedlumLlm.similarity(t1, t2)
    bar_len = round(sim * 25)
    bar = String.duplicate("█", bar_len) <> String.duplicate("░", 25 - bar_len)
    IO.puts("      #{String.pad_trailing(t1, 20)} <-> #{String.pad_trailing(t2, 22)} #{Float.round(sim, 3)} #{bar}")
  end)

  IO.puts("")
end)

# -----------------------------------------------------------------------------
# 4. Finding Similar Documents
# -----------------------------------------------------------------------------
IO.puts("4. Finding Similar Documents (Semantic Search)")
IO.puts(String.duplicate("-", 60))

corpus = [
  "Patient with acute myocardial infarction requiring PCI",
  "Uncontrolled diabetes with HbA1c of 10.2%",
  "Severe asthma exacerbation requiring nebulizer",
  "Traumatic brain injury from motor vehicle accident",
  "Congestive heart failure with reduced ejection fraction",
  "Chronic kidney disease stage 3b on dialysis",
  "Post-operative knee replacement rehabilitation",
  "Acute stroke with left-sided hemiparesis"
]

query = "cardiac problems and heart disease"
IO.puts("   Query: \"#{query}\"")
IO.puts("   Searching #{length(corpus)} documents...\n")

{:ok, results} = MedlumLlm.Embedder.find_similar(query, corpus, top_k: 3)

IO.puts("   Top 3 most relevant documents:")
Enum.with_index(results, 1)
|> Enum.each(fn {{doc, score}, rank} ->
  bar_len = round(score * 20)
  bar = String.duplicate("█", bar_len)
  IO.puts("   #{rank}. [#{Float.round(score, 3)}] #{bar}")
  IO.puts("      #{doc}")
end)

IO.puts("""

================================================================================
  Example Complete
================================================================================
""")
