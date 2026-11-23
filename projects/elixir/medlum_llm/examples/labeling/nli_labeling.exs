# NLI Labeling Example
#
# Demonstrates building NLI samples and labels for CVL training.
#
# Run with: mix run examples/labeling/nli_labeling.exs

alias MedlumLlm.Labeling.{NLI, Schemas, SampleBuilder, LabelBuilder}

IO.puts("=== NLI Labeling Example ===\n")

# === NLI Type Conversions ===

IO.puts("1. NLI Type Conversions")
IO.puts("   verdict_to_label(:entailment) = #{inspect(NLI.verdict_to_label(:entailment))}")
IO.puts("   verdict_to_label(:contradiction) = #{inspect(NLI.verdict_to_label(:contradiction))}")
IO.puts("   verdict_to_label(:neutral) = #{inspect(NLI.verdict_to_label(:neutral))}")
IO.puts("")
IO.puts("   label_to_verdict(\"CONTRADICTION\") = #{inspect(NLI.label_to_verdict("CONTRADICTION"))}")
IO.puts("   valid_label?(\"ENTAILMENT\") = #{inspect(NLI.valid_label?("ENTAILMENT"))}")
IO.puts("   valid_labels() = #{inspect(NLI.valid_labels())}")
IO.puts("")

# === Build NLI Schema ===

IO.puts("2. NLI Schema")
schema = Schemas.nli_schema(tenant_id: "medlum", namespace: "cvl")
IO.puts("   Schema ID: #{schema.id}")
IO.puts("   Tenant: #{schema.tenant_id}")
IO.puts("   Fields: #{length(schema.fields)}")

for field <- schema.fields do
  IO.puts("   - #{field.name}: #{field.type}#{if field.required, do: " (required)", else: ""}")
end

IO.puts("")

# === Build NLI Sample ===

IO.puts("3. Building NLI Sample")

premise = """
Discharge Summary: Patient is a 65-year-old male with type 2 diabetes mellitus.
Current medications include metformin 500mg BID and lisinopril 10mg daily.
HbA1c was 7.2% on 2026-01-14.
"""

hypothesis = "The patient is taking metformin 1000mg daily."

sample = SampleBuilder.build_nli_sample(
  premise,
  hypothesis,
  tenant_id: "medlum",
  namespace: "cvl",
  source_run_id: "eval_9f2a1c0d7b8e4a11",
  model: "openbio_8b",
  model_confidence: 0.85
)

IO.puts("   Sample ID: #{sample.id}")
IO.puts("   Pipeline: #{sample.pipeline_id}")
IO.puts("   Task Type: #{sample.payload["task_type"]}")
IO.puts("   Premise (truncated): #{String.slice(sample.payload["premise"], 0, 50)}...")
IO.puts("   Hypothesis: #{sample.payload["hypothesis"]}")
IO.puts("   Source: #{sample.metadata["source"]}")
IO.puts("   Model: #{sample.metadata["model"]}")
IO.puts("")

# === Build Human Label ===

IO.puts("4. Building Human Label")

label = LabelBuilder.build_nli_label(%{
  assignment_id: "assign_001",
  sample_id: sample.id,
  queue_id: "cvl_nli_queue",
  tenant_id: "medlum",
  namespace: "cvl",
  user_id: "annotator_dr_smith",
  verdict: :contradiction,
  time_spent_ms: 32_000,
  confidence: 5,
  reasoning: """
  The source document clearly states metformin 500mg twice daily (1000mg total),
  but the hypothesis claims 1000mg once daily. The dosing frequency is incorrect.
  """,
  evidence_spans: "metformin 500mg BID",
  difficulty: "easy"
})

IO.puts("   Label ID: #{label.id}")
IO.puts("   User: #{label.user_id}")
IO.puts("   NLI Label: #{label.values["nli_label"]}")
IO.puts("   Confidence: #{label.values["confidence"]}")
IO.puts("   Evidence: #{label.values["evidence_spans"]}")
IO.puts("   Time: #{label.time_spent_ms}ms")
IO.puts("")

# === JSON Serialization ===

IO.puts("5. JSON Serialization")
{:ok, sample_json} = Jason.encode(sample, pretty: true)
IO.puts("   Sample JSON (truncated):")
IO.puts("   #{String.slice(sample_json, 0, 200)}...")
IO.puts("")

{:ok, label_json} = Jason.encode(label, pretty: true)
IO.puts("   Label JSON (truncated):")
IO.puts("   #{String.slice(label_json, 0, 200)}...")
IO.puts("")

IO.puts("=== Example Complete ===")
