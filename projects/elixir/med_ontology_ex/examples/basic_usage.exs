#!/usr/bin/env elixir

# Basic Usage Examples for med_ontology_ex
#
# This script demonstrates the core functionality of the med_ontology_ex library
# for looking up, searching, and validating medical terminology codes.
#
# Run with: mix run examples/basic_usage.exs

IO.puts("=== med_ontology_ex Basic Usage Examples ===\n")

# Start the application
Application.ensure_all_started(:med_ontology_ex)

#
# 1. SNOMED-CT Examples
#
IO.puts("--- SNOMED-CT Examples ---")

# Lookup a concept by SCTID
IO.puts("\nLooking up Type 2 Diabetes (44054006)...")

case MedOntology.lookup(:snomed_ct, "44054006") do
  {:ok, concept} ->
    IO.puts("  Code: #{concept.code}")
    IO.puts("  Display: #{concept.display}")
    IO.puts("  FSN: #{concept.fully_specified_name}")
    IO.puts("  Semantic Type: #{List.first(concept.semantic_types)}")
    IO.puts("  Active: #{concept.active}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Search for concepts by text
IO.puts("\nSearching for 'hypertension'...")

case MedOntology.search(:snomed_ct, "hypertension", limit: 5) do
  {:ok, results} ->
    Enum.each(results, fn result ->
      IO.puts(
        "  #{result.concept.code}: #{result.concept.display} (score: #{Float.round(result.score, 2)})"
      )
    end)

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Check validity
IO.puts("\nValidating codes...")
IO.puts("  44054006 valid? #{MedOntology.valid?(:snomed_ct, "44054006")}")
IO.puts("  INVALID123 valid? #{MedOntology.valid?(:snomed_ct, "INVALID123")}")

# Check is-a relationships
IO.puts("\nChecking is-a relationships...")
IO.puts("  Type 2 DM (44054006) is-a Diabetes mellitus (73211009)? #{MedOntology.SnomedCT.is_a?("44054006", "73211009")}")

# Get ancestors
IO.puts("\nGetting ancestors of Type 2 Diabetes...")

case MedOntology.ancestors(:snomed_ct, "44054006", max_depth: 3) do
  {:ok, ancestors} ->
    Enum.each(ancestors, fn ancestor ->
      IO.puts("  #{ancestor.code}: #{ancestor.display}")
    end)

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

#
# 2. RxNorm Examples
#
IO.puts("\n--- RxNorm Examples ---")

# Lookup a medication by RxCUI
IO.puts("\nLooking up Metformin 500mg (861004)...")

case MedOntology.lookup(:rxnorm, "861004") do
  {:ok, concept} ->
    IO.puts("  Code: #{concept.code}")
    IO.puts("  Display: #{concept.display}")
    IO.puts("  Term Type: #{List.first(concept.semantic_types)}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Normalize a drug string to RxNorm concept
IO.puts("\nNormalizing 'metformin 500mg'...")

case MedOntology.RxNorm.normalize("metformin 500mg") do
  {:ok, concept} ->
    IO.puts("  Normalized to: #{concept.code} - #{concept.display}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Get drug class information
IO.puts("\nGetting drug class for metformin (861004)...")

case MedOntology.RxNorm.drug_class("861004") do
  {:ok, classes} ->
    IO.puts("  ATC: #{inspect(classes.atc)}")
    IO.puts("  VA Class: #{inspect(classes.va_class)}")
    IO.puts("  NDF-RT: #{inspect(classes.ndf_rt)}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Get ingredients
IO.puts("\nGetting ingredients for metformin 500mg (861004)...")

case MedOntology.RxNorm.ingredients("861004") do
  {:ok, ingredients} ->
    Enum.each(ingredients, fn ing ->
      IO.puts("  #{ing.code}: #{ing.display}")
    end)

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Get NDC codes
IO.puts("\nGetting NDC codes for metformin 500mg (861004)...")

case MedOntology.RxNorm.ndc_codes("861004") do
  {:ok, ndcs} ->
    IO.puts("  NDC codes: #{Enum.take(ndcs, 5) |> Enum.join(", ")}...")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Get dose form and strength
IO.puts("\nGetting dose form and strength...")

case MedOntology.RxNorm.dose_form("861004") do
  {:ok, form} ->
    IO.puts("  Dose form: #{form}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

case MedOntology.RxNorm.strength("861004") do
  {:ok, strength} ->
    IO.puts("  Strength: #{strength.value} #{strength.unit}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

#
# 3. ICD-10 Examples
#
IO.puts("\n--- ICD-10 Examples ---")

# Lookup a code
IO.puts("\nLooking up E11.9 (Type 2 DM without complications)...")

case MedOntology.lookup(:icd10, "E11.9") do
  {:ok, concept} ->
    IO.puts("  Code: #{concept.code}")
    IO.puts("  Display: #{concept.display}")
    IO.puts("  Billable: #{concept.properties[:billable]}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Validate format
IO.puts("\nValidating ICD-10 formats...")
IO.puts("  E11.9 valid format? #{MedOntology.ICD10.valid_format?("E11.9")}")
IO.puts("  E11.99999 valid format? #{MedOntology.ICD10.valid_format?("E11.99999")}")
IO.puts("  INVALID valid format? #{MedOntology.ICD10.valid_format?("INVALID")}")

# Check billability
IO.puts("\nChecking billability...")
IO.puts("  E11.9 billable? #{MedOntology.ICD10.billable?("E11.9")}")
IO.puts("  E11 billable? #{MedOntology.ICD10.billable?("E11")}")

# Get hierarchy information
IO.puts("\nGetting hierarchy for E11.9...")

case MedOntology.ICD10.hierarchy("E11.9") do
  {:ok, hierarchy} ->
    IO.puts("  Chapter: #{hierarchy.chapter} - #{hierarchy.chapter_title}")
    IO.puts("  Block: #{hierarchy.block} - #{hierarchy.block_title}")
    IO.puts("  Category: #{hierarchy.category} - #{hierarchy.category_title}")
    IO.puts("  Code: #{hierarchy.code}")
    IO.puts("  Description: #{hierarchy.description}")
    IO.puts("  Billable: #{hierarchy.billable}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Search ICD-10
IO.puts("\nSearching for 'diabetes' in ICD-10...")

case MedOntology.search(:icd10, "diabetes", limit: 5) do
  {:ok, results} ->
    Enum.each(results, fn result ->
      IO.puts(
        "  #{result.concept.code}: #{result.concept.display} (score: #{Float.round(result.score, 2)})"
      )
    end)

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

#
# 4. LOINC Examples
#
IO.puts("\n--- LOINC Examples ---")

# Lookup a code
IO.puts("\nLooking up Glucose (2345-7)...")

case MedOntology.lookup(:loinc, "2345-7") do
  {:ok, concept} ->
    IO.puts("  Code: #{concept.code}")
    IO.puts("  Display: #{concept.display}")
    IO.puts("  Component: #{concept.properties[:component]}")
    IO.puts("  System: #{concept.properties[:system]}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Get LOINC parts (6-part axis)
IO.puts("\nGetting LOINC parts for Hemoglobin A1c (4548-4)...")

case MedOntology.LOINC.parts("4548-4") do
  {:ok, parts} ->
    IO.puts("  Component: #{parts.component}")
    IO.puts("  Property: #{parts.property}")
    IO.puts("  Time Aspect: #{parts.time_aspect}")
    IO.puts("  System: #{parts.system}")
    IO.puts("  Scale Type: #{parts.scale_type}")
    IO.puts("  Method Type: #{parts.method_type || "N/A"}")

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Get reference range
IO.puts("\nGetting reference range for Glucose (2345-7)...")

case MedOntology.LOINC.reference_range("2345-7") do
  {:ok, range} ->
    IO.puts("  Name: #{range.name}")
    IO.puts("  Normal range: #{range.low}-#{range.high} #{range.unit}")

    if range[:critical_low] || range[:critical_high] do
      IO.puts("  Critical low: #{range[:critical_low] || "N/A"}")
      IO.puts("  Critical high: #{range[:critical_high] || "N/A"}")
    end

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

# Evaluate lab values
IO.puts("\nEvaluating lab values...")

values_to_test = [
  {"2345-7", 85, "Glucose 85 mg/dL"},
  {"2345-7", 150, "Glucose 150 mg/dL"},
  {"2345-7", 35, "Glucose 35 mg/dL"},
  {"4548-4", 5.2, "HbA1c 5.2%"},
  {"4548-4", 7.2, "HbA1c 7.2%"},
  {"4548-4", 12.0, "HbA1c 12.0%"}
]

Enum.each(values_to_test, fn {code, value, label} ->
  case MedOntology.LOINC.evaluate_value(code, value) do
    {:ok, status} ->
      IO.puts("  #{label} -> #{status}")

    {:error, reason} ->
      IO.puts("  #{label} -> Error: #{inspect(reason)}")
  end
end)

# Check if code is a panel
IO.puts("\nChecking panel codes...")
IO.puts("  24323-8 (BMP) is panel? #{MedOntology.LOINC.panel?("24323-8")}")
IO.puts("  2345-7 (Glucose) is panel? #{MedOntology.LOINC.panel?("2345-7")}")

# Get panel members
IO.puts("\nGetting panel members for Basic Metabolic Panel (24323-8)...")

case MedOntology.LOINC.panel_members("24323-8") do
  {:ok, members} ->
    Enum.each(members, fn member ->
      IO.puts("  #{member.code}: #{member.display}")
    end)

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

#
# 5. Cross-Ontology Mapping
#
IO.puts("\n--- Cross-Ontology Mapping ---")

IO.puts("\nMapping SNOMED-CT 44054006 (Type 2 DM) to ICD-10...")

case MedOntology.map(:snomed_ct, "44054006", :icd10) do
  {:ok, mappings} ->
    Enum.each(mappings, fn m ->
      IO.puts("  #{m.source_system}:#{m.source_code} -> #{m.target_system}:#{m.target_code}")
      IO.puts("    Equivalence: #{m.equivalence}")
    end)

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

IO.puts("\nGetting all mappings for SNOMED-CT 44054006...")

case MedOntology.all_mappings(:snomed_ct, "44054006") do
  {:ok, all_maps} ->
    Enum.each(all_maps, fn {target_system, mappings} ->
      IO.puts("  To #{target_system}:")

      Enum.each(mappings, fn m ->
        IO.puts("    -> #{m.target_code} (#{m.equivalence})")
      end)
    end)

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

#
# 6. Batch Lookup
#
IO.puts("\n--- Batch Lookup ---")

IO.puts("\nBatch lookup of ICD-10 codes...")
codes = ["E11.9", "I10", "J06.9", "INVALID", "M54.5"]

case MedOntology.lookup_batch(:icd10, codes) do
  {:ok, results} ->
    Enum.each(results, fn {code, concept} ->
      if concept do
        IO.puts("  #{code}: #{concept.display}")
      else
        IO.puts("  #{code}: Not found")
      end
    end)

  {:error, reason} ->
    IO.puts("  Error: #{inspect(reason)}")
end

#
# 7. Cache Statistics
#
IO.puts("\n--- Cache Statistics ---")
stats = MedOntology.cache_stats()

IO.puts("\nCache entries by ontology:")

Enum.each([:snomed_ct, :rxnorm, :icd10, :loinc], fn ontology ->
  ontology_stats = Map.get(stats, ontology, %{})
  size = ontology_stats[:size] || 0
  memory = ontology_stats[:memory_bytes] || 0
  memory_mb = Float.round(memory / 1_048_576, 2)
  IO.puts("  #{ontology}: #{size} entries (#{memory_mb} MB)")
end)

IO.puts("\n=== Basic Usage Examples Complete ===")
