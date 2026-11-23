#!/usr/bin/env elixir

# Batch Processing Examples for med_ontology_ex
#
# This script demonstrates efficient batch processing patterns for
# high-throughput medical terminology operations.
#
# Key patterns:
#   - Parallel processing with Task.async_stream
#   - Batch lookups for multiple codes
#   - Concurrent enrichment of clinical data
#   - Efficient cache utilization
#
# Run with: mix run examples/batch_processing.exs

IO.puts("=== Batch Processing Examples ===\n")

Application.ensure_all_started(:med_ontology_ex)

defmodule BatchExample do
  @moduledoc """
  Examples of batch processing patterns for medical terminology lookups.
  """

  # ============================================================================
  # Medication Batch Processing
  # ============================================================================

  @doc """
  Process a medication list in parallel.

  Normalizes medication strings to RxNorm concepts concurrently.
  """
  def process_medications(med_strings) do
    IO.puts("Processing #{length(med_strings)} medications in parallel...")
    start_time = System.monotonic_time(:millisecond)

    results =
      med_strings
      |> Task.async_stream(
        fn med ->
          case MedOntology.RxNorm.normalize(med) do
            {:ok, concept} ->
              {:ok, med, concept}

            {:error, reason} ->
              {:error, med, reason}
          end
        end,
        max_concurrency: 10,
        timeout: 10_000
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, :timeout, reason}
      end)

    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("Completed in #{elapsed}ms")

    results
  end

  @doc """
  Enrich medication data with drug class and ingredient information.
  """
  def enrich_medications(rxcuis) do
    IO.puts("Enriching #{length(rxcuis)} medications with class and ingredient data...")
    start_time = System.monotonic_time(:millisecond)

    results =
      rxcuis
      |> Task.async_stream(
        fn rxcui ->
          # Parallel fetch of multiple data types
          concept_task = Task.async(fn -> MedOntology.lookup(:rxnorm, rxcui) end)
          class_task = Task.async(fn -> MedOntology.RxNorm.drug_class(rxcui) end)
          ingredients_task = Task.async(fn -> MedOntology.RxNorm.ingredients(rxcui) end)

          # Await all results
          concept = Task.await(concept_task)
          classes = Task.await(class_task)
          ingredients = Task.await(ingredients_task)

          %{
            rxcui: rxcui,
            concept: elem(concept, 1),
            classes: (case classes do {:ok, c} -> c; _ -> %{} end),
            ingredients: (case ingredients do {:ok, i} -> Enum.map(i, & &1.display); _ -> [] end)
          }
        end,
        max_concurrency: 5,
        timeout: 15_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("Completed in #{elapsed}ms")

    results
  end

  # ============================================================================
  # ICD-10 Batch Validation
  # ============================================================================

  @doc """
  Validate a list of ICD-10 codes in batch.

  Returns validation status and billability for each code.
  """
  def validate_icd10_codes(codes) do
    IO.puts("Validating #{length(codes)} ICD-10 codes...")
    start_time = System.monotonic_time(:millisecond)

    # Use lookup_batch for efficient processing
    {:ok, lookup_results} = MedOntology.lookup_batch(:icd10, codes)

    results =
      Enum.map(codes, fn code ->
        case Map.get(lookup_results, code) do
          nil ->
            {code, %{valid: false, billable: false, description: nil}}

          concept ->
            {code,
             %{
               valid: true,
               billable: concept.properties[:billable] || false,
               description: concept.display
             }}
        end
      end)

    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("Completed in #{elapsed}ms")

    results
  end

  @doc """
  Find all billable codes for a list of category codes.
  """
  def expand_to_billable(category_codes) do
    IO.puts("Expanding #{length(category_codes)} categories to billable codes...")

    category_codes
    |> Task.async_stream(
      fn code ->
        case MedOntology.ICD10.descendants(code, limit: 50) do
          {:ok, descendants} ->
            billable =
              descendants
              |> Enum.filter(&(&1.properties[:billable] == true))
              |> Enum.map(& &1.code)

            {code, billable}

          _ ->
            {code, []}
        end
      end,
      max_concurrency: 10
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  # ============================================================================
  # Lab Result Enrichment
  # ============================================================================

  @doc """
  Enrich lab results with LOINC information and reference ranges.
  """
  def enrich_lab_results(lab_results) do
    IO.puts("Enriching #{length(lab_results)} lab results...")
    start_time = System.monotonic_time(:millisecond)

    results =
      Enum.map(lab_results, fn %{name: name, value: value} = result ->
        enrichment =
          case find_loinc_code(name) do
            {:ok, code, display} ->
              reference = case MedOntology.LOINC.reference_range(code) do
                {:ok, range} -> range
                _ -> nil
              end

              status = case MedOntology.LOINC.evaluate_value(code, value) do
                {:ok, s} -> s
                _ -> :unknown
              end

              %{
                loinc_code: code,
                loinc_name: display,
                reference_range: reference,
                status: status
              }

            {:error, _} ->
              %{loinc_code: nil, error: "Lab test not found in LOINC"}
          end

        Map.merge(result, enrichment)
      end)

    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("Completed in #{elapsed}ms")

    results
  end

  defp find_loinc_code(name) do
    # Common lab name to LOINC code mapping
    common_codes = %{
      "Glucose" => "2345-7",
      "Hemoglobin A1c" => "4548-4",
      "Creatinine" => "2160-0",
      "Potassium" => "2823-3",
      "Sodium" => "2951-2",
      "BUN" => "3094-0",
      "Cholesterol" => "2093-3",
      "LDL" => "2089-1",
      "HDL" => "2085-9"
    }

    case Map.get(common_codes, name) do
      nil ->
        case MedOntology.LOINC.search(name, limit: 1) do
          {:ok, [match | _]} -> {:ok, match.concept.code, match.concept.display}
          _ -> {:error, :not_found}
        end

      code ->
        case MedOntology.lookup(:loinc, code) do
          {:ok, concept} -> {:ok, code, concept.display}
          _ -> {:error, :not_found}
        end
    end
  end

  # ============================================================================
  # Cross-Ontology Batch Mapping
  # ============================================================================

  @doc """
  Map a batch of SNOMED-CT codes to ICD-10.
  """
  def batch_snomed_to_icd10(snomed_codes) do
    IO.puts("Mapping #{length(snomed_codes)} SNOMED-CT codes to ICD-10...")
    start_time = System.monotonic_time(:millisecond)

    results =
      snomed_codes
      |> Task.async_stream(
        fn sctid ->
          case MedOntology.map(:snomed_ct, sctid, :icd10) do
            {:ok, mappings} ->
              icd10_codes = Enum.map(mappings, & &1.target_code)
              {sctid, {:ok, icd10_codes}}

            {:error, reason} ->
              {sctid, {:error, reason}}
          end
        end,
        max_concurrency: 10
      )
      |> Enum.map(fn {:ok, result} -> result end)
      |> Map.new()

    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("Completed in #{elapsed}ms")

    results
  end

  # ============================================================================
  # Clinical Document Processing
  # ============================================================================

  @doc """
  Process a clinical document with multiple medical entities.

  Demonstrates concurrent processing of different entity types.
  """
  def process_clinical_document(doc) do
    IO.puts("Processing clinical document with concurrent entity resolution...")
    start_time = System.monotonic_time(:millisecond)

    # Process different entity types concurrently
    tasks = %{
      medications:
        Task.async(fn ->
          Enum.map(doc.medications, fn med ->
            case MedOntology.RxNorm.normalize(med) do
              {:ok, concept} -> %{original: med, rxcui: concept.code, display: concept.display}
              _ -> %{original: med, rxcui: nil, error: "Not found"}
            end
          end)
        end),
      diagnoses:
        Task.async(fn ->
          Enum.map(doc.diagnoses, fn diag ->
            case MedOntology.search(:snomed_ct, diag, limit: 1) do
              {:ok, [match | _]} ->
                %{original: diag, sctid: match.concept.code, display: match.concept.display}

              _ ->
                %{original: diag, sctid: nil, error: "Not found"}
            end
          end)
        end),
      labs:
        Task.async(fn ->
          Enum.map(doc.labs, fn lab ->
            case find_loinc_code(lab.name) do
              {:ok, code, display} ->
                status = case MedOntology.LOINC.evaluate_value(code, lab.value) do
                  {:ok, s} -> s
                  _ -> :unknown
                end
                Map.merge(lab, %{loinc_code: code, loinc_display: display, status: status})

              _ ->
                Map.put(lab, :error, "LOINC not found")
            end
          end)
        end)
    }

    # Await all results
    result = %{
      medications: Task.await(tasks.medications),
      diagnoses: Task.await(tasks.diagnoses),
      labs: Task.await(tasks.labs)
    }

    elapsed = System.monotonic_time(:millisecond) - start_time
    IO.puts("Completed in #{elapsed}ms")

    result
  end
end

# ============================================================================
# Run Examples
# ============================================================================

# Example 1: Medication batch processing
IO.puts("\n--- Example 1: Medication Batch Processing ---\n")

medications = [
  "metformin 500mg",
  "lisinopril 10mg",
  "atorvastatin 20mg",
  "amlodipine 5mg",
  "omeprazole 20mg",
  "aspirin 81mg",
  "gabapentin 300mg",
  "invalid drug xyz"
]

results = BatchExample.process_medications(medications)

Enum.each(results, fn
  {:ok, original, concept} ->
    IO.puts("  #{original}")
    IO.puts("    -> #{concept.code}: #{concept.display}")

  {:error, original, reason} ->
    IO.puts("  #{original}")
    IO.puts("    -> Error: #{inspect(reason)}")
end)

# Example 2: ICD-10 batch validation
IO.puts("\n--- Example 2: ICD-10 Batch Validation ---\n")

icd_codes = ["E11.9", "I10", "J06.9", "INVALID", "M54.5", "E11", "K21.0", "ZZZ.99"]

results = BatchExample.validate_icd10_codes(icd_codes)

Enum.each(results, fn {code, %{valid: valid, billable: billable, description: desc}} ->
  status = if valid, do: "[VALID]", else: "[INVALID]"
  billable_str = if billable, do: "(billable)", else: "(not billable)"
  desc_str = if desc, do: " - #{desc}", else: ""
  IO.puts("  #{code}: #{status} #{billable_str}#{desc_str}")
end)

# Example 3: Lab result enrichment
IO.puts("\n--- Example 3: Lab Result Enrichment ---\n")

lab_results = [
  %{name: "Glucose", value: 95.0, unit: "mg/dL"},
  %{name: "Hemoglobin A1c", value: 7.2, unit: "%"},
  %{name: "Creatinine", value: 1.1, unit: "mg/dL"},
  %{name: "Potassium", value: 4.5, unit: "mEq/L"},
  %{name: "Sodium", value: 140.0, unit: "mEq/L"},
  %{name: "LDL", value: 130.0, unit: "mg/dL"}
]

results = BatchExample.enrich_lab_results(lab_results)

Enum.each(results, fn result ->
  IO.puts("  #{result.name}: #{result.value} #{result.unit}")

  if result[:loinc_code] do
    IO.puts("    LOINC: #{result.loinc_code} - #{result.loinc_name}")
    IO.puts("    Status: #{result.status}")

    if result.reference_range do
      range = result.reference_range
      IO.puts("    Reference: #{range.low}-#{range.high} #{range.unit}")
    end
  else
    IO.puts("    Error: #{result[:error]}")
  end
end)

# Example 4: Clinical document processing
IO.puts("\n--- Example 4: Clinical Document Processing ---\n")

clinical_doc = %{
  medications: [
    "metformin 500mg",
    "lisinopril 20mg",
    "atorvastatin 40mg"
  ],
  diagnoses: [
    "type 2 diabetes mellitus",
    "essential hypertension",
    "hyperlipidemia"
  ],
  labs: [
    %{name: "Glucose", value: 126.0, unit: "mg/dL"},
    %{name: "Hemoglobin A1c", value: 7.5, unit: "%"},
    %{name: "Creatinine", value: 0.9, unit: "mg/dL"}
  ]
}

result = BatchExample.process_clinical_document(clinical_doc)

IO.puts("\nMedications:")
Enum.each(result.medications, fn med ->
  if med[:rxcui] do
    IO.puts("  #{med.original} -> #{med.rxcui}: #{med.display}")
  else
    IO.puts("  #{med.original} -> #{med[:error]}")
  end
end)

IO.puts("\nDiagnoses:")
Enum.each(result.diagnoses, fn diag ->
  if diag[:sctid] do
    IO.puts("  #{diag.original} -> #{diag.sctid}: #{diag.display}")
  else
    IO.puts("  #{diag.original} -> #{diag[:error]}")
  end
end)

IO.puts("\nLab Results:")
Enum.each(result.labs, fn lab ->
  status_emoji = case lab[:status] do
    :normal -> "OK"
    :high -> "HIGH"
    :low -> "LOW"
    :critical_high -> "CRITICAL HIGH"
    :critical_low -> "CRITICAL LOW"
    _ -> "?"
  end

  if lab[:loinc_code] do
    IO.puts("  #{lab.name}: #{lab.value} #{lab.unit} [#{status_emoji}]")
    IO.puts("    LOINC: #{lab.loinc_code}")
  else
    IO.puts("  #{lab.name}: #{lab.value} #{lab.unit} [#{lab[:error]}]")
  end
end)

# Example 5: Medication enrichment with drug classes
IO.puts("\n--- Example 5: Medication Enrichment with Drug Classes ---\n")

rxcuis = ["861004", "197361", "83367", "617310"]

results = BatchExample.enrich_medications(rxcuis)

Enum.each(results, fn med ->
  IO.puts("  RxCUI: #{med.rxcui}")

  if med.concept do
    IO.puts("    Name: #{med.concept.display}")
    IO.puts("    TTY: #{List.first(med.concept.semantic_types)}")
  end

  if med.classes[:atc] && length(med.classes[:atc]) > 0 do
    IO.puts("    ATC Classes: #{Enum.join(med.classes[:atc], ", ")}")
  end

  if length(med.ingredients) > 0 do
    IO.puts("    Ingredients: #{Enum.join(med.ingredients, ", ")}")
  end

  IO.puts("")
end)

# Example 6: Cache performance demonstration
IO.puts("\n--- Example 6: Cache Performance Demonstration ---\n")

# First pass - cache is cold
IO.puts("First pass (cold cache):")
start = System.monotonic_time(:millisecond)
Enum.each(1..10, fn _ ->
  MedOntology.lookup(:icd10, "E11.9")
  MedOntology.lookup(:icd10, "I10")
  MedOntology.lookup(:icd10, "J06.9")
end)
cold_time = System.monotonic_time(:millisecond) - start
IO.puts("  30 lookups completed in #{cold_time}ms")

# Second pass - cache is warm
IO.puts("Second pass (warm cache):")
start = System.monotonic_time(:millisecond)
Enum.each(1..100, fn _ ->
  MedOntology.lookup(:icd10, "E11.9")
  MedOntology.lookup(:icd10, "I10")
  MedOntology.lookup(:icd10, "J06.9")
end)
warm_time = System.monotonic_time(:millisecond) - start
IO.puts("  300 lookups completed in #{warm_time}ms")
IO.puts("  Average: #{Float.round(warm_time / 300, 3)}ms per lookup")

# Cache statistics
IO.puts("\n--- Cache Statistics ---\n")
stats = MedOntology.cache_stats()

Enum.each([:snomed_ct, :rxnorm, :icd10, :loinc], fn ontology ->
  ontology_stats = Map.get(stats, ontology, %{})
  size = ontology_stats[:size] || 0
  memory = ontology_stats[:memory_bytes] || 0
  memory_kb = Float.round(memory / 1024, 2)
  IO.puts("  #{ontology}: #{size} entries (#{memory_kb} KB)")
end)

IO.puts("\n=== Batch Processing Examples Complete ===")
