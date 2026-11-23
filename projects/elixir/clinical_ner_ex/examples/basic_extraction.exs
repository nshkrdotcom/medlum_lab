#!/usr/bin/env elixir

# Basic Extraction Examples for clinical_ner_ex
#
# Run with: mix run examples/basic_extraction.exs

IO.puts("=== clinical_ner_ex Basic Extraction Examples ===\n")

# Ensure the application is started
Application.ensure_all_started(:clinical_ner_ex)

#
# 1. Extract all entity types from a clinical note
#
IO.puts("--- Extract All Entities ---")

text = """
72 y/o male with h/o HTN, T2DM on metformin 1000mg BID.
Labs: A1c 7.2% (H), Cr 1.3 mg/dL.
Presenting with chest pain, r/o ACS.
Plan: EKG, troponins, cardiology consult.
"""

IO.puts("Input text:")
IO.puts(text)
IO.puts("")

case ClinicalNerEx.extract(text, link_ontologies: false) do
  {:ok, entities} ->
    IO.puts("Found #{length(entities)} entities:\n")

    Enum.each(entities, fn entity ->
      IO.puts("  Type: #{entity.type}")
      IO.puts("  Text: \"#{entity.text}\"")
      IO.puts("  Span: #{entity.start_offset}-#{entity.end_offset}")
      IO.puts("  Confidence: #{Float.round(entity.confidence, 2)}")
      IO.puts("  Attributes: #{inspect(entity.attributes, pretty: true)}")
      IO.puts("")
    end)

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

#
# 2. Extract specific entity types
#
IO.puts("\n--- Extract Medications Only ---")

med_text = "Patient on lisinopril 10mg daily, atorvastatin 40mg at bedtime, and aspirin 81mg."

IO.puts("Input: #{med_text}")
IO.puts("")

case ClinicalNerEx.extract_medications(med_text, link_ontologies: false) do
  {:ok, medications} ->
    IO.puts("Found #{length(medications)} medications:")

    Enum.each(medications, fn med ->
      IO.puts("  #{med.text}")
      IO.puts("    Drug: #{med.attributes[:drug_name]}")
      IO.puts("    Dose: #{med.attributes[:dose]} #{med.attributes[:dose_unit]}")

      if med.attributes[:frequency] do
        IO.puts("    Frequency: #{med.attributes[:frequency]}")
      end

      IO.puts("")
    end)

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

#
# 3. Extract lab values
#
IO.puts("\n--- Extract Lab Values ---")

lab_text = "Labs show: Glucose 125 mg/dL (H), HbA1c 6.8%, Na 140, K 4.2, Cr 0.9"

IO.puts("Input: #{lab_text}")
IO.puts("")

case ClinicalNerEx.extract_lab_values(lab_text, link_ontologies: false) do
  {:ok, labs} ->
    IO.puts("Found #{length(labs)} lab values:")

    Enum.each(labs, fn lab ->
      name = lab.attributes[:lab_name] || "unknown"
      value = lab.attributes[:value]
      unit = lab.attributes[:unit] || ""

      IO.puts("  #{name}: #{value} #{unit}")

      if lab.attributes[:abnormal_flag] do
        IO.puts("    Flag: #{lab.attributes[:abnormal_flag]}")
      end

      IO.puts("")
    end)

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

#
# 4. Extract diagnoses
#
IO.puts("\n--- Extract Diagnoses ---")

dx_text = "PMH: HTN, DM, COPD. Presenting with suspected pneumonia. R/o PE."

IO.puts("Input: #{dx_text}")
IO.puts("")

case ClinicalNerEx.extract_diagnoses(dx_text, link_ontologies: false) do
  {:ok, diagnoses} ->
    IO.puts("Found #{length(diagnoses)} diagnoses:")

    Enum.each(diagnoses, fn dx ->
      condition = dx.attributes[:condition] || dx.text
      status = dx.attributes[:status] || :unknown
      IO.puts("  #{condition} (#{status})")
    end)

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

#
# 5. Extract procedures
#
IO.puts("\n--- Extract Procedures ---")

proc_text = "Patient is s/p CABG x3, scheduled for colonoscopy. EKG and chest CT ordered."

IO.puts("Input: #{proc_text}")
IO.puts("")

case ClinicalNerEx.extract_procedures(proc_text, link_ontologies: false) do
  {:ok, procedures} ->
    IO.puts("Found #{length(procedures)} procedures:")

    Enum.each(procedures, fn proc ->
      name = proc.attributes[:procedure_name] || proc.text
      status = proc.attributes[:status] || :unknown
      abbrev = proc.attributes[:abbreviation]

      if abbrev do
        IO.puts("  #{abbrev} (#{name}) - #{status}")
      else
        IO.puts("  #{name} - #{status}")
      end
    end)

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

#
# 6. Extract temporal expressions
#
IO.puts("\n--- Extract Temporal Expressions ---")

temp_text = "Started on 1/15/2026, continue for 2 weeks. Follow up in 3 months."

IO.puts("Input: #{temp_text}")
IO.puts("")

case ClinicalNerEx.extract_temporal(temp_text, link_ontologies: false) do
  {:ok, temporals} ->
    IO.puts("Found #{length(temporals)} temporal expressions:")

    Enum.each(temporals, fn temp ->
      type = temp.attributes[:temporal_type]
      IO.puts("  \"#{temp.text}\" (#{type})")
      IO.puts("    Value: #{inspect(temp.attributes[:value])}")

      if temp.attributes[:unit] do
        IO.puts("    Unit: #{temp.attributes[:unit]}")
      end

      IO.puts("")
    end)

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

#
# 7. Method comparison
#
IO.puts("\n--- Method Comparison ---")

sample = "metformin 500mg BID"

IO.puts("Text: #{sample}")
IO.puts("")

# Rule-based
{:ok, rule_based} = ClinicalNerEx.extract(sample, method: :rule_based, link_ontologies: false)
IO.puts("Rule-based: #{length(rule_based)} entities")

Enum.each(rule_based, fn e ->
  IO.puts("  #{e.text} (conf: #{Float.round(e.confidence, 2)})")
end)

# Hybrid (same as rule_based for now, transformer stub returns empty)
{:ok, hybrid} = ClinicalNerEx.extract(sample, method: :hybrid, link_ontologies: false)
IO.puts("Hybrid: #{length(hybrid)} entities")

Enum.each(hybrid, fn e ->
  IO.puts("  #{e.text} (conf: #{Float.round(e.confidence, 2)})")
end)

#
# 8. Batch extraction
#
IO.puts("\n--- Batch Extraction ---")

texts = [
  "Patient on metformin 500mg",
  "Labs: A1c 6.5%",
  "History of diabetes"
]

IO.puts("Processing #{length(texts)} texts in batch...")

{:ok, results} = ClinicalNerEx.extract_batch(texts, link_ontologies: false)

Enum.with_index(results, 1)
|> Enum.each(fn {entities, idx} ->
  IO.puts("  Text #{idx}: #{length(entities)} entities found")
end)

#
# 9. Configuration
#
IO.puts("\n--- Current Configuration ---")
config = ClinicalNerEx.config()
IO.puts("Default method: #{config.default_method}")
IO.puts("Extraction timeout: #{config.extraction_timeout_ms}ms")
IO.puts("Ontology linking: #{config.enable_ontology_linking}")

IO.puts("Confidence thresholds:")

Enum.each(config.confidence_thresholds, fn {type, threshold} ->
  IO.puts("  #{type}: #{threshold}")
end)

IO.puts("\n=== Examples Complete ===")
