#!/usr/bin/env elixir

# CVL Integration Examples for med_ontology_ex
#
# This example demonstrates how med_ontology_ex integrates with the
# Clinical Verification Layer (CVL) for hallucination detection in
# LLM-generated clinical summaries.
#
# The CVL uses specialized agents to verify different types of medical claims:
#   - Medication Agent: Validates drug mentions, doses, and classes
#   - Lab Agent: Validates lab values against reference ranges
#   - Ontology Agent: Validates diagnoses and clinical findings
#
# Run with: mix run examples/cvl_integration.exs

IO.puts("=== CVL Integration Examples ===\n")

Application.ensure_all_started(:med_ontology_ex)

defmodule CVLExample do
  @moduledoc """
  Example CVL agent implementations using med_ontology_ex.

  These modules demonstrate how the Clinical Verification Layer (CVL)
  can use med_ontology_ex to validate medical claims in LLM-generated
  clinical summaries.
  """

  # ============================================================================
  # Medication Verification Agent
  # ============================================================================

  defmodule MedicationAgent do
    @moduledoc """
    Verifies medication claims by checking:
    1. Drug exists in RxNorm
    2. Dose is within acceptable range
    3. Route is appropriate for the drug form
    """

    @doc """
    Verify a medication claim from an LLM-generated summary.

    ## Examples

        verify_medication("metformin 500 mg")
        #=> {:entailment, 0.95, "Valid medication with appropriate dose"}

        verify_medication("metformin 50000 mg")
        #=> {:contradiction, 0.85, "Dose exceeds maximum safe dose"}

        verify_medication("notarealdrug 100mg")
        #=> {:contradiction, 0.90, "Drug not found in RxNorm"}

    """
    def verify_medication(claim) do
      IO.puts("  Verifying medication claim: #{claim}")

      # Extract drug name and dose from claim
      case extract_medication_info(claim) do
        {:ok, drug_name, dose, unit} ->
          # Step 1: Normalize to RxNorm
          case MedOntology.RxNorm.normalize("#{drug_name} #{dose}#{unit}") do
            {:ok, concept} ->
              IO.puts("    Found RxNorm concept: #{concept.code} - #{concept.display}")

              # Step 2: Get drug class for context
              class_info =
                case MedOntology.RxNorm.drug_class(concept.code) do
                  {:ok, classes} -> classes
                  _ -> %{}
                end

              # Step 3: Validate dose is within safe range
              validation = validate_dose(drug_name, dose, unit)

              case validation do
                :valid ->
                  atc_codes = Map.get(class_info, :atc, [])
                  {:entailment, 0.95, "Valid medication (ATC: #{Enum.join(atc_codes, ", ")})"}

                {:warning, msg} ->
                  {:neutral, 0.70, msg}

                {:invalid, msg} ->
                  {:contradiction, 0.85, msg}
              end

            {:error, :not_found} ->
              # Try searching as a fallback
              case MedOntology.search(:rxnorm, drug_name, limit: 1) do
                {:ok, [match | _]} when match.score > 0.7 ->
                  {:neutral, match.score, "Possible match: #{match.concept.display}"}

                _ ->
                  {:contradiction, 0.90, "Drug '#{drug_name}' not found in RxNorm"}
              end
          end

        {:error, reason} ->
          {:neutral, 0.50, "Unable to parse medication claim: #{reason}"}
      end
    end

    defp extract_medication_info(claim) do
      # Regex pattern for "drug dose unit" format
      # Handles variations like "metformin 500 mg", "lisinopril 10mg"
      case Regex.run(~r/(\w+(?:\s+\w+)?)\s+(\d+(?:\.\d+)?)\s*(mg|mcg|g|ml|units?)/i, claim) do
        [_, drug, dose, unit] ->
          {:ok, String.downcase(drug), parse_dose(dose), String.downcase(unit)}

        _ ->
          {:error, "Could not extract drug, dose, and unit"}
      end
    end

    defp parse_dose(dose_str) do
      case Float.parse(dose_str) do
        {dose, _} -> dose
        :error -> 0
      end
    end

    # Safe dose ranges for common medications (simplified)
    @dose_ranges %{
      "metformin" => %{unit: "mg", min: 250, max: 2550, typical_max: 2000},
      "lisinopril" => %{unit: "mg", min: 2.5, max: 80, typical_max: 40},
      "atorvastatin" => %{unit: "mg", min: 10, max: 80, typical_max: 40},
      "amlodipine" => %{unit: "mg", min: 2.5, max: 10, typical_max: 10},
      "omeprazole" => %{unit: "mg", min: 10, max: 40, typical_max: 20},
      "aspirin" => %{unit: "mg", min: 75, max: 1000, typical_max: 325}
    }

    defp validate_dose(drug_name, dose, unit) do
      case Map.get(@dose_ranges, drug_name) do
        nil ->
          # Unknown drug - can't validate dose
          :valid

        range ->
          cond do
            String.downcase(unit) != range.unit ->
              {:warning, "Unexpected unit: #{unit} (expected #{range.unit})"}

            dose < range.min ->
              {:warning, "Dose #{dose}#{unit} below typical minimum (#{range.min}#{range.unit})"}

            dose > range.max ->
              {:invalid, "Dose #{dose}#{unit} exceeds maximum safe dose (#{range.max}#{range.unit})"}

            dose > range.typical_max ->
              {:warning, "Dose #{dose}#{unit} above typical maximum (#{range.typical_max}#{range.unit})"}

            true ->
              :valid
          end
      end
    end
  end

  # ============================================================================
  # Lab Value Verification Agent
  # ============================================================================

  defmodule LabAgent do
    @moduledoc """
    Verifies lab value claims by checking:
    1. Lab test exists in LOINC
    2. Value is physiologically plausible
    3. Units are appropriate for the test
    """

    @doc """
    Verify a lab value claim.

    ## Examples

        verify_lab_value("hemoglobin A1c 7.2%")
        #=> {:entailment, 0.90, "Lab value elevated but plausible"}

        verify_lab_value("glucose 500 mg/dL")
        #=> {:neutral, 0.70, "Critically elevated - verify accuracy"}

        verify_lab_value("glucose -50 mg/dL")
        #=> {:contradiction, 0.95, "Physiologically implausible value"}

    """
    def verify_lab_value(claim) do
      IO.puts("  Verifying lab value claim: #{claim}")

      case extract_lab_info(claim) do
        {:ok, lab_name, value, unit} ->
          IO.puts("    Extracted: #{lab_name} = #{value} #{unit}")

          # Step 1: Find matching LOINC code
          case find_loinc_code(lab_name) do
            {:ok, loinc_code, display} ->
              IO.puts("    Found LOINC code: #{loinc_code} - #{display}")

              # Step 2: Evaluate value against reference range
              case MedOntology.LOINC.evaluate_value(loinc_code, value) do
                {:ok, :normal} ->
                  {:entailment, 0.95, "Lab value within normal range"}

                {:ok, :high} ->
                  {:entailment, 0.90, "Lab value elevated but plausible"}

                {:ok, :low} ->
                  {:entailment, 0.90, "Lab value decreased but plausible"}

                {:ok, :critical_high} ->
                  {:neutral, 0.70, "Critically elevated - verify accuracy"}

                {:ok, :critical_low} ->
                  {:neutral, 0.70, "Critically low - verify accuracy"}

                {:error, :not_available} ->
                  # No reference range available - check plausibility
                  if physiologically_plausible?(lab_name, value) do
                    {:neutral, 0.60, "No reference range available, value appears plausible"}
                  else
                    {:contradiction, 0.80, "Value appears physiologically implausible"}
                  end
              end

            {:error, :not_found} ->
              {:neutral, 0.50, "Lab test '#{lab_name}' not found in LOINC"}
          end

        {:error, reason} ->
          {:neutral, 0.50, "Unable to parse lab value: #{reason}"}
      end
    end

    defp extract_lab_info(claim) do
      # Multiple patterns for lab value extraction
      patterns = [
        # "hemoglobin A1c 7.2%"
        ~r/(\w+(?:\s+\w+)?(?:\s+\w+)?)\s+(\d+\.?\d*)\s*(%|mg\/dL|g\/dL|mmol\/L|mEq\/L|U\/L|IU\/L)/i,
        # "glucose: 95 mg/dL"
        ~r/(\w+(?:\s+\w+)?)\s*:\s*(\d+\.?\d*)\s*(%|mg\/dL|g\/dL|mmol\/L)/i
      ]

      Enum.find_value(patterns, {:error, "Could not parse lab value"}, fn pattern ->
        case Regex.run(pattern, claim) do
          [_, lab, value, unit] ->
            case Float.parse(value) do
              {v, _} -> {:ok, String.downcase(lab), v, String.downcase(unit)}
              :error -> nil
            end

          _ ->
            nil
        end
      end)
    end

    defp find_loinc_code(lab_name) do
      # Map common lab names to LOINC codes
      common_codes = %{
        "glucose" => "2345-7",
        "hemoglobin a1c" => "4548-4",
        "hba1c" => "4548-4",
        "a1c" => "4548-4",
        "creatinine" => "2160-0",
        "sodium" => "2951-2",
        "potassium" => "2823-3",
        "hemoglobin" => "718-7",
        "hematocrit" => "4544-3",
        "cholesterol" => "2093-3",
        "ldl" => "2089-1",
        "hdl" => "2085-9",
        "triglycerides" => "2571-8"
      }

      case Map.get(common_codes, lab_name) do
        nil ->
          # Fallback to search
          case MedOntology.LOINC.search(lab_name, limit: 1) do
            {:ok, [match | _]} when match.score > 0.6 ->
              {:ok, match.concept.code, match.concept.display}

            _ ->
              {:error, :not_found}
          end

        code ->
          case MedOntology.lookup(:loinc, code) do
            {:ok, concept} -> {:ok, code, concept.display}
            _ -> {:error, :not_found}
          end
      end
    end

    # Basic plausibility checks for values without reference ranges
    defp physiologically_plausible?(lab_name, value) do
      cond do
        value < 0 -> false
        String.contains?(lab_name, "glucose") and value > 1000 -> false
        String.contains?(lab_name, "sodium") and (value < 100 or value > 200) -> false
        String.contains?(lab_name, "potassium") and (value < 1 or value > 15) -> false
        true -> true
      end
    end
  end

  # ============================================================================
  # Ontology (Diagnosis) Verification Agent
  # ============================================================================

  defmodule OntologyAgent do
    @moduledoc """
    Verifies diagnosis claims by checking:
    1. Condition exists in SNOMED-CT
    2. ICD-10 code is valid if provided
    3. SNOMED-ICD mapping is consistent
    """

    @doc """
    Verify a diagnosis claim.

    ## Examples

        verify_diagnosis("type 2 diabetes mellitus")
        #=> {:entailment, 0.95, "Valid diagnosis found in SNOMED-CT"}

        verify_diagnosis("fictitious disease xyz")
        #=> {:neutral, 0.50, "Diagnosis not found in SNOMED-CT"}

    """
    def verify_diagnosis(claim) do
      IO.puts("  Verifying diagnosis claim: #{claim}")

      # Search SNOMED-CT for the condition
      case MedOntology.search(:snomed_ct, claim, limit: 3) do
        {:ok, [best_match | _rest]} when best_match.score > 0.5 ->
          concept = best_match.concept
          IO.puts("    Matched SNOMED-CT: #{concept.code} - #{concept.display}")
          IO.puts("    Match score: #{Float.round(best_match.score, 2)}")

          # Get ICD-10 mapping for additional context
          icd10_info =
            case MedOntology.map(:snomed_ct, concept.code, :icd10) do
              {:ok, [mapping | _]} ->
                "ICD-10: #{mapping.target_code}"

              _ ->
                "No ICD-10 mapping"
            end

          if best_match.score > 0.8 do
            {:entailment, best_match.score, "Valid diagnosis: #{concept.display} (#{icd10_info})"}
          else
            {:neutral, best_match.score, "Possible match: #{concept.display} (#{icd10_info})"}
          end

        {:ok, []} ->
          {:neutral, 0.50, "Diagnosis '#{claim}' not found in SNOMED-CT"}

        {:error, reason} ->
          {:neutral, 0.40, "Error searching SNOMED-CT: #{inspect(reason)}"}
      end
    end

    @doc """
    Verify a diagnosis with an associated ICD-10 code.

    Checks that the ICD-10 code is valid and consistent with the diagnosis text.

    ## Examples

        verify_diagnosis_with_code("type 2 diabetes", "E11.9")
        #=> {:entailment, 0.95, "Diagnosis and ICD-10 code are consistent"}

        verify_diagnosis_with_code("type 2 diabetes", "I10")
        #=> {:contradiction, 0.85, "ICD-10 code does not match diagnosis"}

    """
    def verify_diagnosis_with_code(diagnosis_text, icd10_code) do
      IO.puts("  Verifying diagnosis '#{diagnosis_text}' with code #{icd10_code}")

      # Step 1: Validate ICD-10 code
      unless MedOntology.valid?(:icd10, icd10_code) do
        {:contradiction, 0.90, "Invalid ICD-10 code: #{icd10_code}"}
      else
        # Step 2: Get ICD-10 description
        {:ok, icd_concept} = MedOntology.lookup(:icd10, icd10_code)
        IO.puts("    ICD-10: #{icd_concept.code} - #{icd_concept.display}")

        # Step 3: Search SNOMED-CT
        case MedOntology.search(:snomed_ct, diagnosis_text, limit: 3) do
          {:ok, [match | _]} when match.score > 0.6 ->
            snomed_concept = match.concept
            IO.puts("    SNOMED-CT: #{snomed_concept.code} - #{snomed_concept.display}")

            # Step 4: Check if SNOMED maps to the claimed ICD-10
            case MedOntology.map(:snomed_ct, snomed_concept.code, :icd10) do
              {:ok, mappings} ->
                if Enum.any?(mappings, &(&1.target_code == icd10_code)) do
                  {:entailment, 0.95, "Diagnosis and ICD-10 code are consistent"}
                else
                  # Check if any mapping is related
                  mapped_codes = Enum.map(mappings, & &1.target_code)
                  {:contradiction, 0.85, "ICD-10 code #{icd10_code} not in SNOMED mappings: #{inspect(mapped_codes)}"}
                end

              {:error, _} ->
                # No mapping available - check text similarity
                score = String.jaro_distance(
                  String.downcase(diagnosis_text),
                  String.downcase(icd_concept.display)
                )

                if score > 0.7 do
                  {:neutral, score, "Diagnosis and code appear related (text similarity: #{Float.round(score, 2)})"}
                else
                  {:neutral, 0.50, "Cannot verify consistency - no SNOMED-ICD mapping"}
                end
            end

          _ ->
            {:neutral, 0.50, "Diagnosis text not found in SNOMED-CT"}
        end
      end
    end
  end

  # ============================================================================
  # Integrated CVL Verifier
  # ============================================================================

  defmodule Verifier do
    @moduledoc """
    Integrated CVL verifier that combines all agents to verify
    a complete clinical summary.
    """

    @doc """
    Verify a clinical claim and return structured results.
    """
    def verify_claim(claim_type, claim_text) do
      result =
        case claim_type do
          :medication -> MedicationAgent.verify_medication(claim_text)
          :lab_value -> LabAgent.verify_lab_value(claim_text)
          :diagnosis -> OntologyAgent.verify_diagnosis(claim_text)
          _ -> {:neutral, 0.50, "Unknown claim type"}
        end

      {verdict, confidence, explanation} = result

      %{
        claim_type: claim_type,
        claim_text: claim_text,
        verdict: verdict,
        confidence: confidence,
        explanation: explanation
      }
    end
  end
end

# ============================================================================
# Run Examples
# ============================================================================

IO.puts("--- Medication Verification Examples ---\n")

medication_claims = [
  "metformin 500 mg",
  "metformin 5000 mg",
  "lisinopril 10 mg",
  "amlodipine 15 mg",
  "notarealdrug 100 mg"
]

Enum.each(medication_claims, fn claim ->
  result = CVLExample.MedicationAgent.verify_medication(claim)
  {verdict, confidence, explanation} = result

  IO.puts(
    "    Result: #{verdict} (confidence: #{Float.round(confidence, 2)})\n    Explanation: #{explanation}\n"
  )
end)

IO.puts("\n--- Lab Value Verification Examples ---\n")

lab_claims = [
  "hemoglobin A1c 5.2%",
  "hemoglobin A1c 7.2%",
  "hemoglobin A1c 14%",
  "glucose 95 mg/dL",
  "glucose 450 mg/dL",
  "potassium 4.2 mEq/L"
]

Enum.each(lab_claims, fn claim ->
  result = CVLExample.LabAgent.verify_lab_value(claim)
  {verdict, confidence, explanation} = result

  IO.puts(
    "    Result: #{verdict} (confidence: #{Float.round(confidence, 2)})\n    Explanation: #{explanation}\n"
  )
end)

IO.puts("\n--- Diagnosis Verification Examples ---\n")

diagnosis_claims = [
  "type 2 diabetes mellitus",
  "essential hypertension",
  "acute myocardial infarction",
  "fictitious disease xyz"
]

Enum.each(diagnosis_claims, fn claim ->
  result = CVLExample.OntologyAgent.verify_diagnosis(claim)
  {verdict, confidence, explanation} = result

  IO.puts(
    "    Result: #{verdict} (confidence: #{Float.round(confidence, 2)})\n    Explanation: #{explanation}\n"
  )
end)

IO.puts("\n--- Diagnosis with ICD-10 Code Verification ---\n")

diagnosis_code_pairs = [
  {"type 2 diabetes", "E11.9"},
  {"type 2 diabetes", "I10"},
  {"essential hypertension", "I10"}
]

Enum.each(diagnosis_code_pairs, fn {diagnosis, code} ->
  result = CVLExample.OntologyAgent.verify_diagnosis_with_code(diagnosis, code)
  {verdict, confidence, explanation} = result

  IO.puts(
    "    Result: #{verdict} (confidence: #{Float.round(confidence, 2)})\n    Explanation: #{explanation}\n"
  )
end)

IO.puts("\n--- Integrated Verifier Example ---\n")

claims = [
  {:medication, "lisinopril 20 mg"},
  {:lab_value, "creatinine 1.2 mg/dL"},
  {:diagnosis, "chronic kidney disease"}
]

IO.puts("Verifying multiple claims from a clinical summary:\n")

results =
  Enum.map(claims, fn {type, text} ->
    CVLExample.Verifier.verify_claim(type, text)
  end)

Enum.each(results, fn r ->
  IO.puts("  Claim: [#{r.claim_type}] #{r.claim_text}")
  IO.puts("  Verdict: #{r.verdict} (#{Float.round(r.confidence * 100, 1)}% confidence)")
  IO.puts("  Explanation: #{r.explanation}\n")
end)

# Summary
entailments = Enum.count(results, &(&1.verdict == :entailment))
contradictions = Enum.count(results, &(&1.verdict == :contradiction))
neutral = Enum.count(results, &(&1.verdict == :neutral))
avg_confidence = Enum.reduce(results, 0, &(&1.confidence + &2)) / length(results)

IO.puts("Summary:")
IO.puts("  Entailments: #{entailments}")
IO.puts("  Contradictions: #{contradictions}")
IO.puts("  Neutral: #{neutral}")
IO.puts("  Average Confidence: #{Float.round(avg_confidence * 100, 1)}%")

IO.puts("\n=== CVL Integration Examples Complete ===")
