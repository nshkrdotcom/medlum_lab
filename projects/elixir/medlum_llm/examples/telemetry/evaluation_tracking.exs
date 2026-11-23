# Medical Evaluation Tracking Example
#
# This example demonstrates how to use MedlumLlm.Telemetry
# to track a medical AI evaluation run.
#
# Run with: mix run examples/telemetry/evaluation_tracking.exs

alias MedlumLlm.Telemetry.{Experiment, Metrics, Events}
alias CrucibleTelemetry.Store

IO.puts("=== Medical Evaluation Tracking Example ===\n")

# 1. Show available medical events
IO.puts("Available medical events: #{length(Events.medical_events())}")
IO.puts("  - Evaluation: #{length(Events.evaluation_events())}")
IO.puts("  - CVL: #{length(Events.cvl_events())}")
IO.puts("  - Document: #{length(Events.document_events())}")
IO.puts("")

# 2. Start medical evaluation experiment
{:ok, experiment} = Experiment.start_evaluation("example_medqa_eval",
  benchmark: :medqa_zero_shot,
  models: [:biomistral_7b, :openbio_8b],
  seed: 42,
  hypothesis: "BioMistral-7B achieves >70% on MedQA zero-shot"
)

IO.puts("Started experiment: #{experiment.id}")
IO.puts("  Name: #{experiment.name}")
IO.puts("  Tags: #{inspect(experiment.tags)}")
IO.puts("  Metadata: #{inspect(experiment.metadata)}")
IO.puts("")

# 3. Simulate evaluation events
IO.puts("Simulating evaluation events...")

# Simulate sample evaluations
samples = [
  {0, :biomistral_7b, "A", "A", true, 1200},
  {1, :biomistral_7b, "B", "A", false, 1100},
  {2, :biomistral_7b, "C", "C", true, 1300},
  {3, :openbio_8b, "A", "A", true, 800},
  {4, :openbio_8b, "B", "B", true, 850}
]

for {idx, model, predicted, correct, is_correct, latency_ms} <- samples do
  # Emit sample start
  :telemetry.execute(
    [:medlum_llm, :eval, :sample, :start],
    %{system_time: System.system_time()},
    %{run_id: experiment.id, model: model, sample_idx: idx}
  )

  # Simulate processing time
  :timer.sleep(10)

  # Insert event directly into store (since we don't have handlers for medical events yet)
  event = %{
    event_id: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
    event_name: [:medlum_llm, :eval, :sample, :stop],
    timestamp: System.system_time(:microsecond),
    experiment_id: experiment.id,
    experiment_name: experiment.name,
    condition: experiment.condition,
    tags: experiment.tags,
    measurements: %{
      duration: latency_ms * 1_000_000,
      input_tokens: 150,
      output_tokens: 25,
      tokens_per_second: 25.0
    },
    metadata: %{
      run_id: experiment.id,
      model: model,
      sample_idx: idx,
      sample_id: "medqa_#{String.pad_leading(Integer.to_string(idx), 4, "0")}",
      predicted: predicted,
      correct_answer: correct,
      correct: is_correct
    },
    latency_ms: latency_ms / 1.0,
    cost_usd: 0.001,
    success: true
  }

  Store.insert(experiment.id, event)

  IO.puts("  Sample #{idx}: model=#{model}, correct=#{is_correct}, latency=#{latency_ms}ms")
end

IO.puts("")

# 4. Calculate model metrics
IO.puts("Calculating model metrics...")

{:ok, model_metrics} = Metrics.calculate_model_metrics(experiment.id)

for {model, metrics} <- model_metrics do
  IO.puts("  #{model}:")
  IO.puts("    Accuracy: #{Float.round(metrics.accuracy, 3)}")
  IO.puts("    Total samples: #{metrics.total_samples}")
  IO.puts("    Correct: #{metrics.correct}")
  IO.puts("    Latency P50: #{metrics.latency_p50 && Float.round(metrics.latency_p50, 1)}ms")
end

IO.puts("")

# 5. Simulate CVL verification events
IO.puts("Simulating CVL verification events...")

cvl_samples = [
  {:entailment, false, 100.0, 0},
  {:entailment, false, 120.0, 0},
  {:contradiction, true, 150.0, 2},
  {:neutral, true, 180.0, 1},
  {:entailment, false, 90.0, 0}
]

for {verdict, hallucination, latency_ms, disagreements} <- cvl_samples do
  event = %{
    event_id: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
    event_name: [:medlum_llm, :cvl, :verification, :stop],
    timestamp: System.system_time(:microsecond),
    experiment_id: experiment.id,
    experiment_name: experiment.name,
    condition: experiment.condition,
    tags: experiment.tags,
    measurements: %{duration: round(latency_ms * 1_000_000), agent_calls: 5},
    metadata: %{
      verification_id: "cvl_#{System.unique_integer([:positive])}",
      verdict: verdict,
      confidence: 0.9,
      hallucination_detected: hallucination,
      disagreement_count: disagreements
    },
    latency_ms: latency_ms,
    cost_usd: nil,
    success: true
  }

  Store.insert(experiment.id, event)
end

IO.puts("  Inserted #{length(cvl_samples)} CVL verification events")
IO.puts("")

# 6. Calculate CVL metrics
IO.puts("Calculating CVL metrics...")

{:ok, cvl_metrics} = Metrics.calculate_cvl_metrics(experiment.id)

IO.puts("  Total verifications: #{cvl_metrics.total_verifications}")
IO.puts("  CVL accuracy: #{Float.round(cvl_metrics.cvl_accuracy, 3)}")
IO.puts("  Hallucination precision: #{Float.round(cvl_metrics.hallucination_precision, 3)}")
IO.puts("  Hallucination recall: #{Float.round(cvl_metrics.hallucination_recall, 3)}")
IO.puts("  Hallucination F1: #{Float.round(cvl_metrics.hallucination_f1, 3)}")
IO.puts("  Agent agreement rate: #{Float.round(cvl_metrics.agent_agreement_rate, 3)}")
IO.puts("  Mean verification latency: #{Float.round(cvl_metrics.mean_verification_latency_ms, 1)}ms")
IO.puts("")

# 7. Stop experiment
{:ok, _} = CrucibleTelemetry.stop_experiment(experiment.id)
IO.puts("Experiment stopped.")

# 8. Cleanup
CrucibleTelemetry.Experiment.cleanup(experiment.id)
IO.puts("Experiment cleaned up.")

IO.puts("\n=== Example Complete ===")
