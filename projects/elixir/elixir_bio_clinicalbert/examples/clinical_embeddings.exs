#!/usr/bin/env elixir

# Clinical Text Embeddings - Full Demo
# Run with: mix run examples/clinical_embeddings.exs

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
      text: "Patient with history of atrial fibrillation on warfarin. INR therapeutic at 2.3. No signs of bleeding. Continue current anticoagulation regimen. Follow up in 4 weeks."
    },
    %{
      id: 3,
      department: "Endocrinology",
      text: "Type 2 diabetic with poor glycemic control. HbA1c 9.8%. Fasting glucose 245 mg/dL. Increasing metformin to 1000mg BID and adding glipizide 5mg daily. Dietary counseling provided."
    },
    %{
      id: 4,
      department: "Endocrinology",
      text: "Hypothyroidism follow-up. TSH normalized at 2.1 mIU/L on levothyroxine 75mcg. Patient reports improved energy levels. Continue current dose."
    },
    %{
      id: 5,
      department: "Pulmonology",
      text: "COPD exacerbation with increased dyspnea and productive cough. SpO2 88% on room air. CXR shows hyperinflation. Started on prednisone taper and azithromycin. Nebulizer treatments Q4H."
    },
    %{
      id: 6,
      department: "Pulmonology",
      text: "Newly diagnosed asthma. Spirometry shows FEV1/FVC ratio of 0.65, reversible with bronchodilator. Prescribed albuterol inhaler PRN and fluticasone daily."
    },
    %{
      id: 7,
      department: "Orthopedics",
      text: "Left knee MRI reveals complete ACL tear with associated medial meniscus injury. Discussed surgical options including ACL reconstruction. Patient opts for surgery, scheduled in 2 weeks."
    },
    %{
      id: 8,
      department: "Orthopedics",
      text: "Right hip osteoarthritis with bone-on-bone changes on X-ray. Failed conservative management with NSAIDs and physical therapy. Candidate for total hip arthroplasty."
    },
    %{
      id: 9,
      department: "Neurology",
      text: "New onset seizure activity. EEG shows epileptiform discharges in left temporal region. MRI brain unremarkable. Started on levetiracetam 500mg BID. Driving restrictions discussed."
    },
    %{
      id: 10,
      department: "Neurology",
      text: "Migraine with aura, occurring 3-4 times per month. Triggers include stress and sleep deprivation. Starting sumatriptan for acute episodes and propranolol for prophylaxis."
    },
    %{
      id: 11,
      department: "Cardiology",
      text: "Congestive heart failure exacerbation. BNP elevated at 1200 pg/mL. Bilateral lower extremity edema. Increasing furosemide and adding metolazone. Daily weights and sodium restriction."
    },
    %{
      id: 12,
      department: "Emergency",
      text: "MVA victim with suspected cervical spine injury. GCS 15, neurologically intact. C-collar maintained. CT cervical spine negative for fracture. Cleared for collar removal."
    }
  ]

  # ICD-10 codes for classification demo
  @icd10_codes [
    %{code: "I21.0", description: "ST elevation myocardial infarction of anterior wall"},
    %{code: "I48.91", description: "Atrial fibrillation, unspecified"},
    %{code: "E11.65", description: "Type 2 diabetes mellitus with hyperglycemia"},
    %{code: "E03.9", description: "Hypothyroidism, unspecified"},
    %{code: "J44.1", description: "COPD with acute exacerbation"},
    %{code: "J45.20", description: "Mild intermittent asthma, uncomplicated"},
    %{code: "S83.511A", description: "Sprain of anterior cruciate ligament of right knee"},
    %{code: "M16.11", description: "Primary osteoarthritis, right hip"},
    %{code: "G40.209", description: "Epilepsy, unspecified, not intractable"},
    %{code: "G43.109", description: "Migraine with aura, not intractable"},
    %{code: "I50.9", description: "Heart failure, unspecified"},
    %{code: "S12.9XXA", description: "Fracture of neck, unspecified"}
  ]

  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  CLINICAL TEXT EMBEDDINGS DEMONSTRATION")
    IO.puts("  Using Bio_ClinicalBERT via Ollixir + Ollama")
    IO.puts(String.duplicate("=", 70) <> "\n")

    case ElixirBioClinicalbert.health_check() do
      :ok -> run_all_demos()
      {:error, reason} ->
        IO.puts("ERROR: Cannot connect to Ollama: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp run_all_demos do
    # Pre-compute all embeddings
    IO.puts("Loading and embedding #{length(@clinical_notes)} clinical notes...")
    notes_with_embeddings = embed_notes(@clinical_notes)
    IO.puts("Embedding #{length(@icd10_codes)} ICD-10 codes...")
    codes_with_embeddings = embed_codes(@icd10_codes)
    IO.puts("Done.\n")

    demo_semantic_search(notes_with_embeddings)
    demo_similar_cases(notes_with_embeddings)
    demo_icd10_suggestion(notes_with_embeddings, codes_with_embeddings)
    demo_department_clustering(notes_with_embeddings)
    demo_clinical_qa()

    IO.puts(String.duplicate("=", 70))
    IO.puts("  DEMO COMPLETE")
    IO.puts(String.duplicate("=", 70) <> "\n")
  end

  # ============================================================================
  # DEMO 1: Semantic Search
  # ============================================================================
  defp demo_semantic_search(notes) do
    IO.puts(String.duplicate("-", 70))
    IO.puts("DEMO 1: SEMANTIC SEARCH OVER CLINICAL NOTES")
    IO.puts(String.duplicate("-", 70))
    IO.puts("Find relevant clinical notes using natural language queries.\n")

    queries = [
      "patient having a heart attack",
      "breathing problems and lung disease",
      "blood sugar out of control",
      "knee injury needs surgery"
    ]

    Enum.each(queries, fn query ->
      IO.puts("Query: \"#{query}\"")
      {:ok, query_emb} = ElixirBioClinicalbert.embed(query)

      results =
        notes
        |> Enum.map(fn note ->
          sim = ElixirBioClinicalbert.cosine_similarity(query_emb, note.embedding)
          {note, sim}
        end)
        |> Enum.sort_by(&elem(&1, 1), :desc)
        |> Enum.take(2)

      Enum.with_index(results, 1) |> Enum.each(fn {{note, sim}, rank} ->
        IO.puts("  #{rank}. [#{note.department}] #{String.slice(note.text, 0, 60)}...")
        IO.puts("     Relevance: #{Float.round(sim, 3)}")
      end)
      IO.puts("")
    end)
  end

  # ============================================================================
  # DEMO 2: Similar Case Finding
  # ============================================================================
  defp demo_similar_cases(notes) do
    IO.puts(String.duplicate("-", 70))
    IO.puts("DEMO 2: FIND SIMILAR CLINICAL CASES")
    IO.puts(String.duplicate("-", 70))
    IO.puts("Given a clinical note, find the most similar cases in the database.\n")

    # Pick note #1 (STEMI case) and find similar
    source_note = Enum.at(notes, 0)
    IO.puts("Source Case (ID #{source_note.id}, #{source_note.department}):")
    IO.puts("  #{String.slice(source_note.text, 0, 80)}...\n")

    similar =
      notes
      |> Enum.reject(&(&1.id == source_note.id))
      |> Enum.map(fn note ->
        sim = ElixirBioClinicalbert.cosine_similarity(source_note.embedding, note.embedding)
        {note, sim}
      end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(3)

    IO.puts("Most Similar Cases:")
    Enum.with_index(similar, 1) |> Enum.each(fn {{note, sim}, rank} ->
      bar = String.duplicate("█", round(sim * 30))
      IO.puts("  #{rank}. [ID #{note.id}] #{note.department}")
      IO.puts("     #{String.slice(note.text, 0, 65)}...")
      IO.puts("     Similarity: #{Float.round(sim, 3)} #{bar}")
    end)
    IO.puts("")
  end

  # ============================================================================
  # DEMO 3: ICD-10 Code Suggestion
  # ============================================================================
  defp demo_icd10_suggestion(notes, codes) do
    IO.puts(String.duplicate("-", 70))
    IO.puts("DEMO 3: AUTOMATIC ICD-10 CODE SUGGESTION")
    IO.puts(String.duplicate("-", 70))
    IO.puts("Suggest relevant ICD-10 codes for clinical notes.\n")

    # Pick a few diverse notes
    sample_notes = [Enum.at(notes, 0), Enum.at(notes, 2), Enum.at(notes, 4)]

    Enum.each(sample_notes, fn note ->
      IO.puts("Note (#{note.department}):")
      IO.puts("  #{String.slice(note.text, 0, 70)}...\n")

      suggestions =
        codes
        |> Enum.map(fn code ->
          sim = ElixirBioClinicalbert.cosine_similarity(note.embedding, code.embedding)
          {code, sim}
        end)
        |> Enum.sort_by(&elem(&1, 1), :desc)
        |> Enum.take(3)

      IO.puts("  Suggested ICD-10 Codes:")
      Enum.each(suggestions, fn {code, sim} ->
        IO.puts("    #{code.code} - #{code.description}")
        IO.puts("    Confidence: #{Float.round(sim * 100, 1)}%")
      end)
      IO.puts("")
    end)
  end

  # ============================================================================
  # DEMO 4: Department Clustering
  # ============================================================================
  defp demo_department_clustering(notes) do
    IO.puts(String.duplicate("-", 70))
    IO.puts("DEMO 4: CLINICAL NOTE CLUSTERING BY SPECIALTY")
    IO.puts(String.duplicate("-", 70))
    IO.puts("Analyze how well embeddings separate different medical specialties.\n")

    departments = notes |> Enum.map(& &1.department) |> Enum.uniq()

    IO.puts("Intra-department similarity (notes within same specialty):")
    Enum.each(departments, fn dept ->
      dept_notes = Enum.filter(notes, &(&1.department == dept))
      if length(dept_notes) >= 2 do
        sims = for n1 <- dept_notes, n2 <- dept_notes, n1.id < n2.id do
          ElixirBioClinicalbert.cosine_similarity(n1.embedding, n2.embedding)
        end
        avg_sim = if length(sims) > 0, do: Enum.sum(sims) / length(sims), else: 0
        bar = String.duplicate("█", round(avg_sim * 30))
        IO.puts("  #{String.pad_trailing(dept, 15)} #{Float.round(avg_sim, 3)} #{bar}")
      end
    end)

    IO.puts("\nInter-department similarity (notes across specialties):")
    dept_pairs = for d1 <- departments, d2 <- departments, d1 < d2, do: {d1, d2}
    Enum.take(dept_pairs, 5) |> Enum.each(fn {d1, d2} ->
      notes1 = Enum.filter(notes, &(&1.department == d1))
      notes2 = Enum.filter(notes, &(&1.department == d2))
      sims = for n1 <- notes1, n2 <- notes2 do
        ElixirBioClinicalbert.cosine_similarity(n1.embedding, n2.embedding)
      end
      avg_sim = if length(sims) > 0, do: Enum.sum(sims) / length(sims), else: 0
      bar = String.duplicate("█", round(avg_sim * 30))
      IO.puts("  #{String.pad_trailing("#{d1} <-> #{d2}", 30)} #{Float.round(avg_sim, 3)} #{bar}")
    end)
    IO.puts("")
  end

  # ============================================================================
  # DEMO 5: Clinical Question Answering
  # ============================================================================
  defp demo_clinical_qa do
    IO.puts(String.duplicate("-", 70))
    IO.puts("DEMO 5: CLINICAL CONCEPT RELATIONSHIPS")
    IO.puts(String.duplicate("-", 70))
    IO.puts("Explore semantic relationships between clinical concepts.\n")

    concept_groups = [
      {"Synonyms (should be HIGH similarity)", [
        {"heart attack", "myocardial infarction"},
        {"high blood pressure", "hypertension"},
        {"stroke", "cerebrovascular accident"},
        {"sugar diabetes", "diabetes mellitus"}
      ]},
      {"Related Concepts (should be MEDIUM similarity)", [
        {"chest pain", "heart attack"},
        {"shortness of breath", "COPD"},
        {"headache", "migraine"},
        {"joint pain", "arthritis"}
      ]},
      {"Unrelated Concepts (should be LOW similarity)", [
        {"heart attack", "bone fracture"},
        {"diabetes", "concussion"},
        {"pneumonia", "knee replacement"},
        {"seizure", "appendicitis"}
      ]}
    ]

    Enum.each(concept_groups, fn {group_name, pairs} ->
      IO.puts("#{group_name}:")
      sims = Enum.map(pairs, fn {t1, t2} ->
        {:ok, sim} = ElixirBioClinicalbert.similarity(t1, t2)
        bar = String.duplicate("█", round(sim * 25))
        IO.puts("  #{String.pad_trailing(t1, 22)} <-> #{String.pad_trailing(t2, 22)} #{Float.round(sim, 3)} #{bar}")
        sim
      end)
      avg = Enum.sum(sims) / length(sims)
      IO.puts("  Average: #{Float.round(avg, 3)}\n")
    end)
  end

  # ============================================================================
  # Helpers
  # ============================================================================
  defp embed_notes(notes) do
    texts = Enum.map(notes, & &1.text)
    {:ok, embeddings} = ElixirBioClinicalbert.embed_batch(texts)

    Enum.zip(notes, embeddings)
    |> Enum.map(fn {note, emb} -> Map.put(note, :embedding, emb) end)
  end

  defp embed_codes(codes) do
    texts = Enum.map(codes, & &1.description)
    {:ok, embeddings} = ElixirBioClinicalbert.embed_batch(texts)

    Enum.zip(codes, embeddings)
    |> Enum.map(fn {code, emb} -> Map.put(code, :embedding, emb) end)
  end
end

# Run the demo
ClinicalDemo.run()
