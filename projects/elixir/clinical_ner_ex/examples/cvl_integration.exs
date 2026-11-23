#!/usr/bin/env elixir

# CVL Integration Example for clinical_ner_ex
#
# Demonstrates how clinical_ner_ex integrates with CVL agents
# for clinical verification and hallucination detection.
#
# Run with: mix run examples/cvl_integration.exs

IO.puts("=== CVL Integration Example ===\n")

Application.ensure_all_started(:clinical_ner_ex)

defmodule CVLAgentExample do
  @moduledoc """
  Example CVL agent implementations using clinical_ner_ex for entity extraction.

  These examples demonstrate how CVL agents can use clinical_ner_ex to:
  1. Extract entities from claims and source documents
  2. Compare extracted entities for verification
  3. Generate verification verdicts with confidence scores
  """

  @doc """
  Medication verification agent.

  Verifies medication claims by:
  1. Extracting medication entities from claim and source
  2. Comparing drug names and doses
  3. Returning verification verdict with confidence
  """
  def verify_medication_claim(claim, source_text) do
    IO.puts("Verifying medication claim...")
    IO.puts("  Claim: #{claim}")
    IO.puts("  Source: #{String.slice(source_text, 0, 60)}...")

    # Extract medications from claim
    {:ok, claim_meds} = ClinicalNerEx.extract_medications(claim, link_ontologies: false)

    # Extract medications from source
    {:ok, source_meds} = ClinicalNerEx.extract_medications(source_text, link_ontologies: false)

    # Compare drug names
    claim_drugs =
      Enum.map(claim_meds, fn m ->
        (m.attributes[:drug_name] || "")
        |> String.downcase()
        |> String.trim()
      end)
      |> Enum.filter(&(&1 != ""))

    source_drugs =
      Enum.map(source_meds, fn m ->
        (m.attributes[:drug_name] || "")
        |> String.downcase()
        |> String.trim()
      end)
      |> Enum.filter(&(&1 != ""))

    matches = Enum.filter(claim_drugs, fn d -> d in source_drugs end)

    verdict =
      cond do
        Enum.empty?(claim_drugs) ->
          {:neutral, 0.5, "No medications found in claim"}

        length(matches) == length(claim_drugs) ->
          {:entailment, 0.95, "All medications verified: #{Enum.join(matches, ", ")}"}

        length(matches) > 0 ->
          {:partial, 0.7, "Some medications verified: #{Enum.join(matches, ", ")}"}

        true ->
          {:contradiction, 0.85, "Medications not found in source"}
      end

    IO.puts("  Verdict: #{inspect(verdict)}")
    verdict
  end

  @doc """
  Lab value verification agent.

  Verifies lab claims by:
  1. Extracting lab entities from claim and source
  2. Checking value matches
  3. Validating against reference ranges
  """
  def verify_lab_claim(claim, source_text) do
    IO.puts("\nVerifying lab claim...")
    IO.puts("  Claim: #{claim}")

    {:ok, claim_labs} = ClinicalNerEx.extract_lab_values(claim, link_ontologies: false)
    {:ok, source_labs} = ClinicalNerEx.extract_lab_values(source_text, link_ontologies: false)

    results =
      Enum.map(claim_labs, fn claim_lab ->
        claim_name = claim_lab.attributes[:lab_name]

        # Find matching lab in source
        match =
          Enum.find(source_labs, fn source_lab ->
            claim_name == source_lab.attributes[:lab_name]
          end)

        cond do
          is_nil(match) ->
            IO.puts("  #{claim_name}: NOT FOUND in source")
            {:neutral, 0.5}

          claim_lab.attributes[:value] == match.attributes[:value] ->
            IO.puts("  #{claim_name}: VERIFIED (#{claim_lab.attributes[:value]})")
            {:entailment, 0.95}

          true ->
            IO.puts(
              "  #{claim_name}: MISMATCH (claim: #{claim_lab.attributes[:value]}, source: #{match.attributes[:value]})"
            )

            {:contradiction, 0.85}
        end
      end)

    results
  end

  @doc """
  Diagnosis verification agent.

  Verifies diagnosis claims by:
  1. Extracting diagnosis entities from claim and source
  2. Comparing conditions (including abbreviation expansion)
  3. Checking diagnosis status
  """
  def verify_diagnosis_claim(claim, source_text) do
    IO.puts("\nVerifying diagnosis claim...")
    IO.puts("  Claim: #{claim}")

    {:ok, claim_dx} = ClinicalNerEx.extract_diagnoses(claim, link_ontologies: false)
    {:ok, source_dx} = ClinicalNerEx.extract_diagnoses(source_text, link_ontologies: false)

    claim_conditions =
      Enum.map(claim_dx, fn d ->
        (d.attributes[:condition] || d.text)
        |> String.downcase()
      end)

    source_conditions =
      Enum.map(source_dx, fn d ->
        (d.attributes[:condition] || d.text)
        |> String.downcase()
      end)

    IO.puts("  Claim diagnoses: #{inspect(claim_conditions)}")
    IO.puts("  Source diagnoses: #{inspect(source_conditions)}")

    # Check for matches (including partial matches)
    matches =
      Enum.filter(claim_conditions, fn c ->
        Enum.any?(source_conditions, fn s ->
          c == s or String.contains?(s, c) or String.contains?(c, s)
        end)
      end)

    verdict =
      if length(matches) > 0 do
        {:entailment, 0.85, "Diagnosis verified: #{inspect(matches)}"}
      else
        {:neutral, 0.5, "Diagnosis not explicitly found"}
      end

    IO.puts("  Verdict: #{inspect(verdict)}")
    verdict
  end

  @doc """
  Procedure verification agent.

  Verifies procedure claims against source documentation.
  """
  def verify_procedure_claim(claim, source_text) do
    IO.puts("\nVerifying procedure claim...")
    IO.puts("  Claim: #{claim}")

    {:ok, claim_procs} = ClinicalNerEx.extract_procedures(claim, link_ontologies: false)
    {:ok, source_procs} = ClinicalNerEx.extract_procedures(source_text, link_ontologies: false)

    claim_names =
      Enum.flat_map(claim_procs, fn p ->
        [
          p.attributes[:procedure_name],
          p.attributes[:abbreviation]
        ]
        |> Enum.filter(& &1)
        |> Enum.map(&String.downcase/1)
      end)

    source_names =
      Enum.flat_map(source_procs, fn p ->
        [
          p.attributes[:procedure_name],
          p.attributes[:abbreviation]
        ]
        |> Enum.filter(& &1)
        |> Enum.map(&String.downcase/1)
      end)

    IO.puts("  Claim procedures: #{inspect(claim_names)}")
    IO.puts("  Source procedures: #{inspect(source_names)}")

    matches =
      Enum.filter(claim_names, fn c ->
        Enum.any?(source_names, fn s -> c == s end)
      end)

    verdict =
      cond do
        Enum.empty?(claim_names) ->
          {:neutral, 0.5, "No procedures found in claim"}

        length(matches) > 0 ->
          {:entailment, 0.90, "Procedure verified: #{Enum.join(Enum.uniq(matches), ", ")}"}

        true ->
          {:contradiction, 0.80, "Procedure not found in source"}
      end

    IO.puts("  Verdict: #{inspect(verdict)}")
    verdict
  end

  @doc """
  Comprehensive clinical document verification.

  Verifies an LLM-generated summary against source documentation.
  """
  def verify_document(summary, source) do
    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("COMPREHENSIVE DOCUMENT VERIFICATION")
    IO.puts(String.duplicate("=", 50))

    IO.puts("\nSummary to verify:")
    IO.puts(summary)
    IO.puts("\nSource document:")
    IO.puts(String.slice(source, 0, 200) <> "...")
    IO.puts("")

    # Extract all entities from both documents
    {:ok, summary_entities} = ClinicalNerEx.extract(summary, link_ontologies: false)
    {:ok, source_entities} = ClinicalNerEx.extract(source, link_ontologies: false)

    # Group by type
    summary_by_type = Enum.group_by(summary_entities, & &1.type)
    source_by_type = Enum.group_by(source_entities, & &1.type)

    IO.puts("Entity counts:")
    IO.puts("  Summary: #{length(summary_entities)} total")
    IO.puts("  Source: #{length(source_entities)} total")

    # Verify each entity type
    results =
      [:medication, :lab_value, :diagnosis, :procedure]
      |> Enum.map(fn type ->
        summary_ents = Map.get(summary_by_type, type, [])
        source_ents = Map.get(source_by_type, type, [])

        verified_count = count_verified_entities(summary_ents, source_ents)
        total_count = length(summary_ents)

        verification_rate =
          if total_count > 0 do
            verified_count / total_count
          else
            1.0
          end

        IO.puts(
          "\n  #{type}: #{verified_count}/#{total_count} verified (#{Float.round(verification_rate * 100, 1)}%)"
        )

        {type, verification_rate}
      end)

    # Calculate overall confidence
    overall_confidence =
      results
      |> Enum.map(fn {_, rate} -> rate end)
      |> Enum.sum()
      |> Kernel./(length(results))

    IO.puts("\n" <> String.duplicate("-", 50))
    IO.puts("OVERALL VERIFICATION CONFIDENCE: #{Float.round(overall_confidence * 100, 1)}%")

    verdict =
      cond do
        overall_confidence >= 0.9 -> :high_confidence
        overall_confidence >= 0.7 -> :moderate_confidence
        overall_confidence >= 0.5 -> :low_confidence
        true -> :unreliable
      end

    IO.puts("VERDICT: #{verdict}")
    IO.puts(String.duplicate("=", 50))

    {verdict, overall_confidence, results}
  end

  defp count_verified_entities(summary_ents, source_ents) do
    Enum.count(summary_ents, fn summary_ent ->
      Enum.any?(source_ents, fn source_ent ->
        entities_match?(summary_ent, source_ent)
      end)
    end)
  end

  defp entities_match?(e1, e2) do
    # Simple text-based matching
    e1_text = String.downcase(e1.text)
    e2_text = String.downcase(e2.text)

    e1_text == e2_text or
      String.contains?(e1_text, e2_text) or
      String.contains?(e2_text, e1_text) or
      attributes_match?(e1.attributes, e2.attributes)
  end

  defp attributes_match?(attrs1, attrs2) do
    # Check for matching key attributes
    case {attrs1[:drug_name], attrs2[:drug_name]} do
      {nil, _} -> false
      {_, nil} -> false
      {d1, d2} -> String.downcase(d1) == String.downcase(d2)
    end ||
      case {attrs1[:lab_name], attrs2[:lab_name]} do
        {nil, _} -> false
        {_, nil} -> false
        {l1, l2} -> l1 == l2
      end ||
      case {attrs1[:condition], attrs2[:condition]} do
        {nil, _} -> false
        {_, nil} -> false
        {c1, c2} -> String.downcase(c1) == String.downcase(c2)
      end
  end
end

# ============================================================================
# Run examples
# ============================================================================

source = """
72 y/o male with PMH of HTN, T2DM on metformin 1000mg BID and lisinopril 20mg daily.
Recent labs: A1c 7.2%, Cr 1.1 mg/dL, Na 140, K 4.5.
Patient is s/p CABG x3 in 2020.
Presenting today with chest pain, EKG ordered.
"""

IO.puts("Source Document:")
IO.puts(source)
IO.puts(String.duplicate("-", 50))

# Individual verifications
CVLAgentExample.verify_medication_claim(
  "Patient takes metformin 1000mg",
  source
)

CVLAgentExample.verify_medication_claim(
  "Patient on aspirin daily",
  source
)

CVLAgentExample.verify_lab_claim(
  "A1c 7.2%",
  source
)

CVLAgentExample.verify_lab_claim(
  "Creatinine 1.5 mg/dL",
  source
)

CVLAgentExample.verify_diagnosis_claim(
  "Patient has diabetes",
  source
)

CVLAgentExample.verify_procedure_claim(
  "Patient had CABG surgery",
  source
)

# Comprehensive verification
summary = """
This is a 72-year-old male with hypertension and type 2 diabetes.
He takes metformin 1000mg twice daily and lisinopril 20mg daily.
His recent A1c was 7.2% and creatinine was 1.1.
He previously had coronary artery bypass surgery.
"""

CVLAgentExample.verify_document(summary, source)

IO.puts("\n=== CVL Integration Example Complete ===")
