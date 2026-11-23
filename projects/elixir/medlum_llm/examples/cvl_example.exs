#!/usr/bin/env elixir
# CVL (Clinical Verification Layer) Examples for MedlumLlm
#
# Run with: mix run examples/cvl_example.exs

alias MedlumLlm.CVL.{Verifier, Consensus}
alias MedlumLlm.CVL.{MedicationAgent, LabAgent, OntologyAgent, TemporalAgent, DifferentialAgent}

IO.puts("=== MedlumLlm CVL Verification Example ===\n")

# -----------------------------------------------------------------------------
# 1. List CVL Agents
# -----------------------------------------------------------------------------

IO.puts("1. CVL Agents:")
IO.puts("   Agent                    Weight    Purpose")
IO.puts("   " <> String.duplicate("-", 60))

agents_info = [
  {MedicationAgent, "RxNorm drug verification (safety-critical)"},
  {LabAgent, "LOINC lab value validation"},
  {OntologyAgent, "SNOMED-CT/ICD-10 terminology"},
  {TemporalAgent, "Timeline consistency checking"},
  {DifferentialAgent, "Symptom-diagnosis mapping"}
]

for {agent, purpose} <- agents_info do
  name_str = String.pad_trailing(to_string(agent.name()), 22)
  weight_str = String.pad_trailing("#{agent.weight()}", 10)
  IO.puts("   #{name_str} #{weight_str} #{purpose}")
end
IO.puts("")

total_weight = Consensus.total_weight()
IO.puts("   Total Weight: #{total_weight}")
IO.puts("")

# -----------------------------------------------------------------------------
# 2. Single Agent Verification - Medication
# -----------------------------------------------------------------------------

IO.puts("2. Medication Agent Verification:")

claim1 = "Patient started on metformin 500mg twice daily"
context1 = %{
  conditions: [:diabetes],
  current_medications: [],
  source_index: %{
    medications: [
      %{text: "metformin 500mg BID", doc_id: "note-1"}
    ]
  }
}

IO.puts("   Claim: \"#{claim1}\"")
IO.puts("   Context: diabetes diagnosis, source has metformin mention")
IO.puts("")

med_result = MedicationAgent.verify(claim1, context1)
IO.puts("   MedicationAgent Result:")
IO.puts("     Verdict: #{med_result.verdict}")
IO.puts("     Confidence: #{med_result.confidence}")
if med_result.explanations && length(med_result.explanations) > 0 do
  IO.puts("     Explanation: #{hd(med_result.explanations)}")
end
IO.puts("")

# Unknown medication
claim2 = "Patient started on madeupdrugxyz 1000mg"
med_result2 = MedicationAgent.verify(claim2, context1)
IO.puts("   Unknown Drug Claim: \"#{claim2}\"")
IO.puts("     Verdict: #{med_result2.verdict}")
if med_result2.explanations && length(med_result2.explanations) > 0 do
  IO.puts("     Explanation: #{hd(med_result2.explanations)}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 3. Single Agent Verification - Lab Values
# -----------------------------------------------------------------------------

IO.puts("3. Lab Agent Verification:")

lab_claim = "HbA1c is 7.2%"
lab_context = %{
  source_index: %{
    labs: [
      %{text: "A1c 7.2%", doc_id: "lab-1"}
    ]
  }
}

IO.puts("   Claim: \"#{lab_claim}\"")
lab_result = LabAgent.verify(lab_claim, lab_context)
IO.puts("   LabAgent Result:")
IO.puts("     Verdict: #{lab_result.verdict}")
IO.puts("     Confidence: #{lab_result.confidence}")
IO.puts("")

# Invalid lab value
invalid_lab_claim = "Hemoglobin is 50 g/dL"
invalid_lab_result = LabAgent.verify(invalid_lab_claim, %{source_index: %{}})
IO.puts("   Invalid Lab Claim: \"#{invalid_lab_claim}\"")
IO.puts("     Verdict: #{invalid_lab_result.verdict}")
IO.puts("     (Normal range: 12-17 g/dL)")
IO.puts("")

# -----------------------------------------------------------------------------
# 4. Single Agent Verification - Ontology
# -----------------------------------------------------------------------------

IO.puts("4. Ontology Agent Verification:")

dx_claim = "Patient has type 2 diabetes mellitus"
dx_context = %{
  source_index: %{
    diagnoses: [
      %{text: "type 2 diabetes", doc_id: "note-1", code: "E11.9"}
    ]
  }
}

IO.puts("   Claim: \"#{dx_claim}\"")
ont_result = OntologyAgent.verify(dx_claim, dx_context)
IO.puts("   OntologyAgent Result:")
IO.puts("     Verdict: #{ont_result.verdict}")
IO.puts("     Confidence: #{ont_result.confidence}")
IO.puts("")

# -----------------------------------------------------------------------------
# 5. Single Agent Verification - Temporal
# -----------------------------------------------------------------------------

IO.puts("5. Temporal Agent Verification:")

temporal_claim = "Symptoms started 3 weeks ago"
temporal_context = %{
  source_index: %{},
  documents: ["Patient reports symptoms began approximately 3 weeks prior to visit"]
}

IO.puts("   Claim: \"#{temporal_claim}\"")
temp_result = TemporalAgent.verify(temporal_claim, temporal_context)
IO.puts("   TemporalAgent Result:")
IO.puts("     Verdict: #{temp_result.verdict}")
IO.puts("     Confidence: #{temp_result.confidence}")
IO.puts("")

# Implausible duration
implausible_claim = "Patient has had diabetes for 100 years"
implausible_result = TemporalAgent.verify(implausible_claim, %{source_index: %{}})
IO.puts("   Implausible Claim: \"#{implausible_claim}\"")
IO.puts("     Verdict: #{implausible_result.verdict}")
IO.puts("")

# -----------------------------------------------------------------------------
# 6. Single Agent Verification - Differential
# -----------------------------------------------------------------------------

IO.puts("6. Differential Agent Verification:")

diff_claim = "Patient with chest pain diagnosed with myocardial infarction"
diff_context = %{
  source_index: %{
    diagnoses: [%{text: "myocardial infarction", doc_id: "note-1"}],
    findings: [%{text: "chest pain", doc_id: "note-1"}]
  }
}

IO.puts("   Claim: \"#{diff_claim}\"")
diff_result = DifferentialAgent.verify(diff_claim, diff_context)
IO.puts("   DifferentialAgent Result:")
IO.puts("     Verdict: #{diff_result.verdict}")
IO.puts("     Confidence: #{diff_result.confidence}")
IO.puts("")

# -----------------------------------------------------------------------------
# 7. Full Consensus Verification
# -----------------------------------------------------------------------------

IO.puts("7. Full Consensus Verification (All Agents):")

source_docs = [
  "Patient is a 55-year-old male with type 2 diabetes mellitus.",
  "HbA1c is 7.8%. Fasting glucose 145 mg/dL.",
  "Current medications: lisinopril 10mg daily for hypertension.",
  "Patient reports fatigue for the past 2 weeks."
]

full_context = %{
  documents: source_docs,
  source_index: %{
    medications: [%{text: "lisinopril 10mg daily", doc_id: "doc-3"}],
    labs: [%{text: "HbA1c 7.8%", doc_id: "doc-2"}, %{text: "glucose 145", doc_id: "doc-2"}],
    diagnoses: [%{text: "type 2 diabetes", doc_id: "doc-1"}, %{text: "hypertension", doc_id: "doc-3"}],
    findings: [%{text: "fatigue", doc_id: "doc-4"}]
  },
  demographics: %{age: 55, sex: "male"}
}

claims_to_verify = [
  "Patient has diabetes",
  "Patient takes metformin for diabetes control",
  "Patient's HbA1c is 6.5%",
  "Patient has hypertension",
  "Patient has been fatigued for 2 weeks"
]

IO.puts("   Source Documents:")
for {doc, idx} <- Enum.with_index(source_docs, 1) do
  IO.puts("     #{idx}. #{doc}")
end
IO.puts("")

IO.puts("   Verification Results:")
IO.puts("   " <> String.duplicate("-", 70))

for claim <- claims_to_verify do
  result = Consensus.verify(claim, full_context)

  verdict_str = case result.verdict do
    :entailment -> "ENTAILMENT    "
    :contradiction -> "CONTRADICTION "
    :neutral -> "NEUTRAL       "
  end

  confidence_str = "#{Float.round(result.confidence, 2)}"

  IO.puts("   Claim: \"#{claim}\"")
  IO.puts("     Verdict: #{verdict_str} Confidence: #{confidence_str}")
  IO.puts("")
end

# -----------------------------------------------------------------------------
# 8. Consensus Scoring Details
# -----------------------------------------------------------------------------

IO.puts("8. Consensus Scoring Details:")

test_claim = "Patient takes metformin for diabetes"
test_result = Consensus.verify(test_claim, full_context)

IO.puts("   Claim: \"#{test_claim}\"")
IO.puts("")
IO.puts("   Agent Results:")

for agent_result <- test_result.agent_results do
  name = String.pad_trailing(to_string(agent_result.agent), 20)
  verdict = String.pad_trailing(to_string(agent_result.result.verdict), 14)
  weight = agent_result.weight
  conf = agent_result.result.confidence
  score = Float.round(weight * conf, 3)
  IO.puts("     #{name} #{verdict} weight=#{weight} conf=#{conf} score=#{score}")
end

IO.puts("")
IO.puts("   Weighted Scores:")
IO.puts("     Entailment: #{Float.round(test_result.scores.entailment, 3)}")
IO.puts("     Contradiction: #{Float.round(test_result.scores.contradiction, 3)}")
IO.puts("     Neutral: #{Float.round(test_result.scores.neutral, 3)}")
IO.puts("")
IO.puts("   Final Verdict: #{test_result.verdict}")
IO.puts("   Final Confidence: #{Float.round(test_result.confidence, 3)}")
IO.puts("")

# -----------------------------------------------------------------------------
# 9. Full Summary Verification
# -----------------------------------------------------------------------------

IO.puts("9. Full Summary Verification (Verifier API):")

summary_text = """
55-year-old male diabetic patient on metformin 500mg twice daily.
Recent A1c 7.8% shows good glycemic control. Also takes lisinopril
10mg for hypertension. Reports fatigue for past 2 weeks.
"""

IO.puts("   Summary to verify:")
IO.puts("     " <> String.replace(String.trim(summary_text), "\n", "\n     "))
IO.puts("")

case Verifier.verify_summary(summary_text, source_docs) do
  {:ok, result} ->
    IO.puts("   Summary Verification Result:")
    IO.puts("     Summary Verdict: #{result.summary_verdict}")
    IO.puts("     Summary Confidence: #{Float.round(result.summary_confidence, 3)}")
    IO.puts("     Claims Extracted: #{result.claim_count}")
    IO.puts("     Needs Review: #{result.needs_review_count}")
    IO.puts("")

    if result.claim_count > 0 do
      IO.puts("   Claim-Level Results:")
      for {claim_result, idx} <- Enum.with_index(result.claim_results, 1) do
        claim_text = String.slice(claim_result.claim.text, 0..50)
        IO.puts("     #{idx}. \"#{claim_text}...\"")
        IO.puts("        Verdict: #{claim_result.verdict}, Needs Review: #{claim_result.needs_review}")
      end
    end

  {:error, reason} ->
    IO.puts("   Error: #{inspect(reason)}")
end
IO.puts("")

# -----------------------------------------------------------------------------
# 10. Aggregation Rules
# -----------------------------------------------------------------------------

IO.puts("10. Consensus Aggregation Rules:")

IO.puts("""
   Verdict Determination:

   1. CONTRADICTION takes precedence if:
      contradiction_score > entailment_score * 0.5

   2. ENTAILMENT if:
      entailment_score > neutral_score

   3. NEUTRAL (default):
      When evidence is insufficient or ambiguous

   Agent Weights (Medlum-owned):
     - MedicationAgent: 1.5 (safety-critical)
     - LabAgent: 1.2 (objective values)
     - OntologyAgent: 1.0 (terminology)
     - DifferentialAgent: 1.0 (clinical reasoning)
     - TemporalAgent: 0.8 (higher uncertainty)

   Confidence Calculation:
     max_score / (entailment + contradiction + neutral)
""")

# -----------------------------------------------------------------------------
# 11. Needs Review Flag
# -----------------------------------------------------------------------------

IO.puts("11. Needs Review Criteria:")

IO.puts("""
   A claim needs_review = true when:
     - Verdict is :contradiction (potential hallucination)
     - Verdict is :neutral (insufficient evidence)

   These claims should be surfaced to clinical reviewers
   in the Medlum UX for manual verification.

   Grant Target: >95% of hallucinations flagged for review
""")

# -----------------------------------------------------------------------------
# 12. Source Grounding Semantics
# -----------------------------------------------------------------------------

IO.puts("12. Source-Grounded Verification Semantics:")

IO.puts("""
   ENTAILMENT:
     - Claim is valid AND supported by source documents
     - Example: "Patient has diabetes" when source says "type 2 diabetes mellitus"

   CONTRADICTION:
     - Claim is invalid (bad drug name, impossible lab value)
     - OR claim conflicts with source documents
     - Example: "HbA1c is 6.5%" when source says "HbA1c 7.8%"

   NEUTRAL:
     - Claim may be valid but NOT found in source documents
     - Potential hallucination - needs human review
     - Example: "Patient takes metformin" when source doesn't mention metformin

   This ensures CVL catches both invalid claims AND unsupported claims.
""")

IO.puts("=== CVL Examples Complete ===")
