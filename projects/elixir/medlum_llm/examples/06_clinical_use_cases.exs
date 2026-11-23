#!/usr/bin/env elixir
# Example 06: Comprehensive Clinical Use Cases
#
# This example demonstrates real-world clinical NLP applications:
# - Semantic search over clinical notes
# - ICD-10 code suggestion
# - Clinical note similarity
# - Department clustering analysis
#
# Requires: ollama pull nomic-embed-text
#
# Run: mix run examples/06_clinical_use_cases.exs

Logger.configure(level: :warning)

defmodule ClinicalDemo do
  @moduledoc """
  Demonstrates real-world clinical NLP use cases with embeddings.
  """

  # Sample clinical notes database
  @clinical_notes [
    %{
      id: 1,
      department: "Cardiology",
      text: "65-year-old male presenting with acute chest pain radiating to left arm. ECG shows ST elevation in leads V1-V4. Troponin I elevated at 2.5 ng/mL. Impression: STEMI. Plan: emergent cardiac catheterization."
    },
    %{
      id: 2,
      department: "Cardiology",
      text: "Patient with history of atrial fibrillation on warfarin. INR therapeutic at 2.3. No signs of bleeding. Continue current anticoagulation regimen."
    },
    %{
      id: 3,
      department: "Endocrinology",
      text: "Type 2 diabetic with poor glycemic control. HbA1c 9.8%. Fasting glucose 245 mg/dL. Increasing metformin to 1000mg BID and adding glipizide 5mg daily."
    },
    %{
      id: 4,
      department: "Endocrinology",
      text: "Hypothyroidism follow-up. TSH normalized at 2.1 mIU/L on levothyroxine 75mcg. Patient reports improved energy levels."
    },
    %{
      id: 5,
      department: "Pulmonology",
      text: "COPD exacerbation with increased dyspnea and productive cough. SpO2 88% on room air. Started on prednisone taper and azithromycin."
    },
    %{
      id: 6,
      department: "Pulmonology",
      text: "Newly diagnosed asthma. Spirometry shows FEV1/FVC ratio of 0.65, reversible with bronchodilator. Prescribed albuterol PRN and fluticasone daily."
    },
    %{
      id: 7,
      department: "Orthopedics",
      text: "Left knee MRI reveals complete ACL tear with associated medial meniscus injury. Discussed surgical options including ACL reconstruction."
    },
    %{
      id: 8,
      department: "Neurology",
      text: "New onset seizure activity. EEG shows epileptiform discharges in left temporal region. Started on levetiracetam 500mg BID."
    },
    %{
      id: 9,
      department: "Cardiology",
      text: "Congestive heart failure exacerbation. BNP elevated at 1200 pg/mL. Bilateral lower extremity edema. Increasing furosemide."
    },
    %{
      id: 10,
      department: "Neurology",
      text: "Migraine with aura, occurring 3-4 times per month. Starting sumatriptan for acute episodes and propranolol for prophylaxis."
    }
  ]

  # ICD-10 codes for classification demo
  @icd10_codes [
    %{code: "I21.0", description: "ST elevation myocardial infarction of anterior wall"},
    %{code: "I48.91", description: "Atrial fibrillation, unspecified"},
    %{code: "E11.65", description: "Type 2 diabetes mellitus with hyperglycemia"},
    %{code: "E03.9", description: "Hypothyroidism, unspecified"},
    %{code: "J44.1", description: "COPD with acute exacerbation"},
    %{code: "J45.20", description: "Mild intermittent asthma"},
    %{code: "S83.511A", description: "Sprain of anterior cruciate ligament"},
    %{code: "G40.209", description: "Epilepsy, unspecified"},
    %{code: "I50.9", description: "Heart failure, unspecified"},
    %{code: "G43.109", description: "Migraine with aura"}
  ]

  def run do
    IO.puts("""

    ================================================================================
      Example 06: Comprehensive Clinical Use Cases
    ================================================================================

    Using embeddings for real-world clinical NLP applications.
    """)

    case MedlumLlm.health_check() do
      :ok -> run_all_demos()
      {:error, reason} ->
        IO.puts("ERROR: Cannot connect to Ollama: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp run_all_demos do
    IO.puts("Loading and embedding clinical data...")

    # Pre-compute all embeddings
    notes_with_embeddings = embed_notes(@clinical_notes)
    codes_with_embeddings = embed_codes(@icd10_codes)
    IO.puts("Done. #{length(notes_with_embeddings)} notes, #{length(codes_with_embeddings)} ICD-10 codes.\n")

    demo_semantic_search(notes_with_embeddings)
    demo_icd10_suggestion(notes_with_embeddings, codes_with_embeddings)
    demo_similar_cases(notes_with_embeddings)
    demo_department_clustering(notes_with_embeddings)

    IO.puts("""

    ================================================================================
      Example Complete
    ================================================================================
    """)
  end

  # Demo 1: Semantic Search
  defp demo_semantic_search(notes) do
    IO.puts("1. SEMANTIC SEARCH OVER CLINICAL NOTES")
    IO.puts(String.duplicate("-", 60))

    queries = [
      "patient having a heart attack",
      "breathing problems and lung disease",
      "blood sugar out of control"
    ]

    Enum.each(queries, fn query ->
      IO.puts("\n   Query: \"#{query}\"")
      {:ok, query_emb} = MedlumLlm.embed(query)

      results =
        notes
        |> Enum.map(fn note ->
          sim = MedlumLlm.cosine_similarity(query_emb, note.embedding)
          {note, sim}
        end)
        |> Enum.sort_by(&elem(&1, 1), :desc)
        |> Enum.take(2)

      Enum.with_index(results, 1) |> Enum.each(fn {{note, sim}, rank} ->
        IO.puts("   #{rank}. [#{note.department}] #{String.slice(note.text, 0, 50)}...")
        IO.puts("      Relevance: #{Float.round(sim, 3)}")
      end)
    end)

    IO.puts("")
  end

  # Demo 2: ICD-10 Code Suggestion
  defp demo_icd10_suggestion(notes, codes) do
    IO.puts("\n2. AUTOMATIC ICD-10 CODE SUGGESTION")
    IO.puts(String.duplicate("-", 60))

    sample_notes = Enum.take(notes, 3)

    Enum.each(sample_notes, fn note ->
      IO.puts("\n   Note (#{note.department}):")
      IO.puts("   #{String.slice(note.text, 0, 60)}...\n")

      suggestions =
        codes
        |> Enum.map(fn code ->
          sim = MedlumLlm.cosine_similarity(note.embedding, code.embedding)
          {code, sim}
        end)
        |> Enum.sort_by(&elem(&1, 1), :desc)
        |> Enum.take(2)

      IO.puts("   Suggested ICD-10 Codes:")
      Enum.each(suggestions, fn {code, sim} ->
        confidence = Float.round(sim * 100, 1)
        IO.puts("     #{code.code} - #{code.description} (#{confidence}%)")
      end)
    end)

    IO.puts("")
  end

  # Demo 3: Similar Cases
  defp demo_similar_cases(notes) do
    IO.puts("\n3. FIND SIMILAR CLINICAL CASES")
    IO.puts(String.duplicate("-", 60))

    source_note = Enum.at(notes, 0)
    IO.puts("\n   Source Case (ID #{source_note.id}, #{source_note.department}):")
    IO.puts("   #{String.slice(source_note.text, 0, 70)}...\n")

    similar =
      notes
      |> Enum.reject(&(&1.id == source_note.id))
      |> Enum.map(fn note ->
        sim = MedlumLlm.cosine_similarity(source_note.embedding, note.embedding)
        {note, sim}
      end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(3)

    IO.puts("   Most Similar Cases:")
    Enum.with_index(similar, 1) |> Enum.each(fn {{note, sim}, rank} ->
      bar = String.duplicate("█", round(sim * 25))
      IO.puts("   #{rank}. [ID #{note.id}] #{note.department} - #{Float.round(sim, 3)} #{bar}")
      IO.puts("      #{String.slice(note.text, 0, 60)}...")
    end)

    IO.puts("")
  end

  # Demo 4: Department Clustering
  defp demo_department_clustering(notes) do
    IO.puts("\n4. CLINICAL NOTE CLUSTERING BY SPECIALTY")
    IO.puts(String.duplicate("-", 60))

    departments = notes |> Enum.map(& &1.department) |> Enum.uniq()

    IO.puts("\n   Intra-department similarity (within same specialty):")

    Enum.each(departments, fn dept ->
      dept_notes = Enum.filter(notes, &(&1.department == dept))
      if length(dept_notes) >= 2 do
        sims = for n1 <- dept_notes, n2 <- dept_notes, n1.id < n2.id do
          MedlumLlm.cosine_similarity(n1.embedding, n2.embedding)
        end
        avg_sim = if length(sims) > 0, do: Enum.sum(sims) / length(sims), else: 0
        bar = String.duplicate("█", round(avg_sim * 25))
        IO.puts("   #{String.pad_trailing(dept, 15)} #{Float.round(avg_sim, 3)} #{bar}")
      end
    end)

    IO.puts("\n   Inter-department similarity (across specialties):")

    dept_pairs = for d1 <- departments, d2 <- departments, d1 < d2, do: {d1, d2}

    Enum.take(dept_pairs, 4) |> Enum.each(fn {d1, d2} ->
      notes1 = Enum.filter(notes, &(&1.department == d1))
      notes2 = Enum.filter(notes, &(&1.department == d2))
      sims = for n1 <- notes1, n2 <- notes2 do
        MedlumLlm.cosine_similarity(n1.embedding, n2.embedding)
      end
      avg_sim = if length(sims) > 0, do: Enum.sum(sims) / length(sims), else: 0
      bar = String.duplicate("█", round(avg_sim * 25))
      IO.puts("   #{String.pad_trailing("#{d1} <-> #{d2}", 30)} #{Float.round(avg_sim, 3)} #{bar}")
    end)

    IO.puts("")
  end

  # Helpers
  defp embed_notes(notes) do
    texts = Enum.map(notes, & &1.text)
    {:ok, embeddings} = MedlumLlm.embed_batch(texts)

    Enum.zip(notes, embeddings)
    |> Enum.map(fn {note, emb} -> Map.put(note, :embedding, emb) end)
  end

  defp embed_codes(codes) do
    texts = Enum.map(codes, & &1.description)
    {:ok, embeddings} = MedlumLlm.embed_batch(texts)

    Enum.zip(codes, embeddings)
    |> Enum.map(fn {code, emb} -> Map.put(code, :embedding, emb) end)
  end
end

# Run the demo
ClinicalDemo.run()
