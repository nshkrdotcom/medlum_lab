# CVL Sample Example
#
# Demonstrates building multi-document clinical samples and
# multi-agent verification labels for CVL workflows.
#
# Run with: mix run examples/labeling/cvl_sample.exs

alias MedlumLlm.Labeling.{CVL, ClinicalDocument, SampleBuilder, LabelBuilder, Schemas}

IO.puts("=== CVL Sample Example ===\n")

# === Clinical Documents ===

IO.puts("1. Creating Clinical Documents")

documents = [
  %{
    type: :discharge_summary,
    content: """
    DISCHARGE SUMMARY
    Patient: [De-identified]
    Date: 2026-01-15

    DIAGNOSES:
    1. Type 2 Diabetes Mellitus, E11.9
    2. Hypertension, I10

    MEDICATIONS ON DISCHARGE:
    - Metformin 500mg BID
    - Lisinopril 10mg daily
    - Aspirin 81mg daily

    FOLLOW-UP:
    Endocrinology in 3 months. Repeat HbA1c at that time.
    """,
    date: ~D[2026-01-15],
    provider_type: "endocrinology",
    ontology_codes: %{
      snomed_ct: ["44054006", "38341003"],
      icd10: ["E11.9", "I10"],
      rxnorm: ["861004", "29046", "243670"],
      loinc: []
    }
  },
  %{
    type: :lab_report,
    content: """
    LABORATORY RESULTS
    Date: 2026-01-14

    HbA1c: 7.2% (Reference: 4.0-5.6%)
    Fasting Glucose: 126 mg/dL (Reference: 70-100 mg/dL)
    Creatinine: 0.9 mg/dL (Reference: 0.7-1.3 mg/dL)
    eGFR: >90 mL/min/1.73m2
    """,
    date: ~D[2026-01-14],
    provider_type: "laboratory",
    ontology_codes: %{
      snomed_ct: [],
      icd10: [],
      rxnorm: [],
      loinc: ["4548-4", "2345-7", "2160-0"]
    }
  }
]

IO.puts("   Created #{length(documents)} clinical documents")
for doc <- documents do
  IO.puts("   - #{doc.type}: #{String.slice(doc.content, 0, 50)}...")
end
IO.puts("")

# === Validate Documents ===

IO.puts("2. Validating Documents")
for doc <- documents do
  case ClinicalDocument.validate(doc) do
    {:ok, validated} ->
      IO.puts("   [OK] #{validated.type}")
    {:error, reason} ->
      IO.puts("   [ERROR] #{inspect(reason)}")
  end
end
IO.puts("")

# === Build Clinical Sample ===

IO.puts("3. Building Clinical Sample")

generated_summary = """
Patient is a 65-year-old with well-controlled type 2 diabetes on metformin 1000mg daily.
Recent HbA1c was 7.2%, showing good glycemic control. The patient also has hypertension
managed with lisinopril. Kidney function is normal.
"""

claims = [
  %{"text" => "metformin 1000mg daily", "span" => [52, 74]},
  %{"text" => "well-controlled type 2 diabetes", "span" => [32, 63]}
]

sample = SampleBuilder.build_clinical_sample(
  documents,
  generated_summary,
  tenant_id: "medlum",
  namespace: "cvl",
  claims: claims
)

IO.puts("   Sample ID: #{sample.id}")
IO.puts("   Document count: #{sample.payload["patient_context"]["document_count"]}")
IO.puts("   Claims: #{length(sample.payload["claims"])}")
IO.puts("   Ontology annotations:")
annotations = sample.metadata["ontology_annotations"]
IO.puts("     - SNOMED-CT: #{inspect(annotations["snomed_ct"])}")
IO.puts("     - ICD-10: #{inspect(annotations["icd10"])}")
IO.puts("     - RxNorm: #{inspect(annotations["rxnorm"])}")
IO.puts("     - LOINC: #{inspect(annotations["loinc"])}")
IO.puts("")

# === Multi-Agent Verification ===

IO.puts("4. Multi-Agent Verification")

# Medication Agent
medication_verdict = %{
  verdict: :contradiction,
  confidence: 0.92,
  evidence: ["Dose mismatch: summary says 1000mg daily, discharge says 500mg BID"],
  ontology_codes: ["861004"]
}
{:ok, med_validated} = CVL.validate_agent_verdict(medication_verdict)

# Lab Agent
lab_verdict = %{
  verdict: :entailment,
  confidence: 0.88,
  evidence: ["HbA1c 7.2% matches source lab report"],
  ontology_codes: ["4548-4"]
}
{:ok, lab_validated} = CVL.validate_agent_verdict(lab_verdict)

# Ontology Agent
ontology_verdict = %{
  verdict: :entailment,
  confidence: 0.85,
  evidence: ["Diabetes and hypertension diagnoses consistent"],
  ontology_codes: ["E11.9", "I10"]
}
{:ok, ontology_validated} = CVL.validate_agent_verdict(ontology_verdict)

IO.puts("   Agent verdicts:")
IO.puts("     - Medication: #{med_validated.verdict} (conf: #{med_validated.confidence})")
IO.puts("     - Lab: #{lab_validated.verdict} (conf: #{lab_validated.confidence})")
IO.puts("     - Ontology: #{ontology_validated.verdict} (conf: #{ontology_validated.confidence})")
IO.puts("")

# === Build Agent Labels ===

IO.puts("5. Building Agent Labels")

for {agent_type, verdict, agent_id} <- [
  {:medication, med_validated, "medication_agent_v1"},
  {:lab, lab_validated, "lab_agent_v1"},
  {:ontology, ontology_validated, "ontology_agent_v1"}
] do
  label = LabelBuilder.build_agent_label(
    agent_type,
    verdict,
    assignment_id: "assign_001",
    sample_id: sample.id,
    queue_id: "cvl_agent_queue",
    tenant_id: "medlum",
    agent_id: agent_id,
    time_spent_ms: 150
  )

  IO.puts("   #{label.user_id}: #{label.values["verdict"]}")
end
IO.puts("")

# === Build Consensus Label ===

IO.puts("6. Building Consensus Label")

consensus = %{
  agent_verdicts: %{
    medication: med_validated,
    lab: lab_validated,
    ontology: ontology_validated
  },
  consensus_verdict: :contradiction,
  consensus_method: :weighted_vote,
  dissent_count: 1
}

consensus_label = LabelBuilder.build_consensus_label(
  consensus,
  assignment_id: "assign_001",
  sample_id: sample.id,
  queue_id: "cvl_consensus_queue",
  tenant_id: "medlum",
  time_spent_ms: 450
)

IO.puts("   Consensus verdict: #{consensus_label.values["consensus_verdict"]}")
IO.puts("   Method: #{consensus_label.values["consensus_method"]}")
IO.puts("   Dissent count: #{consensus_label.values["dissent_count"]}")
IO.puts("")

# === Clinical Verification Schema ===

IO.puts("7. Clinical Verification Schema")
cv_schema = Schemas.clinical_verification_schema()
IO.puts("   Schema ID: #{cv_schema.id}")
IO.puts("   Fields:")
for field <- cv_schema.fields do
  range = if field.min && field.max, do: " (#{field.min}-#{field.max})", else: ""
  IO.puts("     - #{field.name}: #{field.type}#{range}")
end
IO.puts("")

# === JSON Output ===

IO.puts("8. JSON Output")
{:ok, json} = Jason.encode(sample, pretty: true)
IO.puts("   Sample serialized to JSON: #{String.length(json)} bytes")

{:ok, label_json} = Jason.encode(consensus_label, pretty: true)
IO.puts("   Consensus label serialized: #{String.length(label_json)} bytes")
IO.puts("")

IO.puts("=== Example Complete ===")
