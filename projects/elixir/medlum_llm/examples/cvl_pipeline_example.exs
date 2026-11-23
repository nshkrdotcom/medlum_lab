# CVL Training Pipeline Example
#
# This example demonstrates how to use the CVL training data pipeline
# to process evaluation failures and generate NLI training data.
#
# Run with: mix run examples/cvl_pipeline_example.exs

alias MedlumLlm.CVL.TrainingPipeline
alias MedlumLlm.CVL.Stages.{NormalizeText, ClaimExtraction, NLIPairGenerator}
alias MedlumLlm.CVL.Measurements.{MedicationAgent, AgentConsensus, Confidence}

# =============================================================================
# Example 1: Running the Full Pipeline
# =============================================================================

IO.puts("\n=== Example 1: Running the Full Pipeline ===\n")

# Run the pipeline with default configuration
# This reads from priv/eval_results/*.json
case TrainingPipeline.run(results_dir: "priv/eval_results") do
  {:ok, stats} ->
    IO.puts("Pipeline completed successfully!")
    IO.puts("  Samples processed: #{stats.total_samples}")
    IO.puts("  Duration: #{stats.duration_ms}ms")

  {:error, reason} ->
    IO.puts("Pipeline failed: #{inspect(reason)}")
end

# =============================================================================
# Example 2: Running Individual Stages
# =============================================================================

IO.puts("\n=== Example 2: Running Individual Stages ===\n")

# Create a sample manually for testing
sample = %Forge.Sample{
  id: "example_001",
  pipeline: :cvl_training,
  data: %{
    source_document: """
    Patient is a 65-year-old male with type 2 diabetes mellitus.
    Current medications include metformin 500mg twice daily and
    lisinopril 10mg daily. Recent labs show HbA1c of 7.2%.
    Blood pressure today is 128/82 mmHg.
    """,
    generated_summary: """
    65-year-old male diabetic patient taking metformin 1000mg daily.
    A1c is 7.2%, indicating good glycemic control.
    """,
    error_type: :incorrect,
    model: :openbio_8b,
    benchmark: :medqa_zero_shot
  },
  measurements: %{},
  status: :pending,
  created_at: DateTime.utc_now()
}

# Stage 1: Normalize text
IO.puts("Running NormalizeText stage...")
{:ok, normalized} = NormalizeText.process(sample)
IO.puts("  Text normalized ✓")

# Stage 2: Extract claims
IO.puts("Running ClaimExtraction stage...")
{:ok, with_claims} = ClaimExtraction.process(normalized)
IO.puts("  Extracted #{length(with_claims.data.claims)} claims:")

for claim <- Enum.take(with_claims.data.claims, 5) do
  IO.puts("    [#{claim.type}] #{String.slice(claim.text, 0, 50)}...")
end

# Stage 3: Generate NLI pairs
IO.puts("Running NLIPairGenerator stage...")
{:ok, with_nli} = NLIPairGenerator.process(with_claims)
IO.puts("  Generated #{length(with_nli.data.nli_pairs)} NLI pairs")

nli_pair = hd(with_nli.data.nli_pairs)
IO.puts("  First pair:")
IO.puts("    Premise: #{String.slice(nli_pair.premise, 0, 50)}...")
IO.puts("    Hypothesis: #{String.slice(nli_pair.hypothesis, 0, 50)}...")
IO.puts("    Label: #{nli_pair.label}")

# =============================================================================
# Example 3: Running Measurements
# =============================================================================

IO.puts("\n=== Example 3: Running Measurements ===\n")

# Compute medication agent measurement
IO.puts("Running MedicationAgent...")
{:ok, med_results} = MedicationAgent.compute([with_nli])
med_result = med_results[with_nli.id]

IO.puts("  Verdict: #{med_result.verdict}")
IO.puts("  Confidence: #{med_result.confidence}")
IO.puts("  Medications found: #{length(med_result.medications_found)}")

for med <- med_result.medications_found do
  if med.drug_name do
    IO.puts("    - #{med.drug_name}")
  end
end

# =============================================================================
# Example 4: Computing Consensus
# =============================================================================

IO.puts("\n=== Example 4: Computing Consensus ===\n")

# Create sample with pre-computed agent results
sample_with_measurements = %{with_nli |
  measurements: %{
    medication: %{verdict: :contradiction, confidence: 0.85, reasoning: "Dose mismatch"},
    lab: %{verdict: :entailment, confidence: 0.9, reasoning: "Lab values verified"},
    ontology: %{verdict: :entailment, confidence: 0.8, reasoning: "Diagnoses verified"},
    temporal: %{verdict: :neutral, confidence: 0.7, reasoning: "No temporal claims"},
    differential: %{verdict: :entailment, confidence: 0.75, reasoning: "Symptoms support diagnosis"}
  }
}

IO.puts("Agent verdicts:")
for {agent, result} <- sample_with_measurements.measurements do
  IO.puts("  #{agent}: #{result.verdict} (#{result.confidence})")
end

# Compute consensus
{:ok, consensus_results} = AgentConsensus.compute([sample_with_measurements])
consensus = consensus_results[sample_with_measurements.id]

IO.puts("\nConsensus result:")
IO.puts("  Verdict: #{consensus.verdict}")
IO.puts("  Confidence: #{Float.round(consensus.confidence, 3)}")
IO.puts("  Agreement: #{Float.round(consensus.agreement * 100, 1)}%")
IO.puts("  Reasoning: #{consensus.reasoning}")

# =============================================================================
# Example 5: Computing Final Confidence
# =============================================================================

IO.puts("\n=== Example 5: Computing Final Confidence ===\n")

# Add consensus to measurements
sample_with_consensus = %{sample_with_measurements |
  measurements: Map.put(sample_with_measurements.measurements, :consensus, consensus)
}

# Compute confidence
{:ok, confidence_results} = Confidence.compute([sample_with_consensus])
confidence = confidence_results[sample_with_consensus.id]

IO.puts("Confidence result:")
IO.puts("  Raw score: #{Float.round(confidence.score, 3)}")
IO.puts("  Calibrated score: #{Float.round(confidence.calibrated_score, 3)}")
IO.puts("  Level: #{confidence.confidence_level}")
IO.puts("  Reasoning: #{confidence.reasoning}")

# =============================================================================
# Example 6: Filtering Samples for Review
# =============================================================================

IO.puts("\n=== Example 6: Determining Review Status ===\n")

thresholds = Confidence.thresholds()
IO.puts("Confidence thresholds:")
IO.puts("  High: >= #{thresholds.high} (auto-accept)")
IO.puts("  Low: < #{thresholds.low} (requires review)")

case confidence.confidence_level do
  :high ->
    IO.puts("\nThis sample has HIGH confidence - can be auto-accepted")
  :medium ->
    IO.puts("\nThis sample has MEDIUM confidence - may benefit from review")
  :low ->
    IO.puts("\nThis sample has LOW confidence - should be sent to Anvil for human labeling")
end

# =============================================================================
# Example 7: Streaming Pipeline
# =============================================================================

IO.puts("\n=== Example 7: Streaming Pipeline ===\n")

IO.puts("Streaming samples with backpressure...")
IO.puts("(Note: Requires eval results in priv/eval_results/)")

# Stream samples and take first 5
# samples_stream = TrainingPipeline.stream(results_dir: "priv/eval_results")
# |> Stream.take(5)
# |> Enum.to_list()
#
# IO.puts("Processed #{length(samples_stream)} samples via streaming")

IO.puts("\n=== All Examples Complete ===\n")
