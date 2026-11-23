# Grant Report Generation Example
#
# This example demonstrates how to generate grant-ready reports
# from medical evaluation data using MedlumLlm.Telemetry.
#
# Run with: mix run examples/telemetry/grant_report.exs

alias MedlumLlm.Telemetry.{Experiment, Metrics, Reports, Baselines}
alias CrucibleTelemetry.Store

IO.puts("=== Grant Report Generation Example ===\n")

# 1. Start experiment with evaluation context
{:ok, experiment} = Experiment.start_evaluation("clinical_eval_q2_medqa",
  benchmark: :medqa_zero_shot,
  models: [:biomistral_7b],
  seed: 42,
  hypothesis: "BioMistral-7B achieves >70% on MedQA zero-shot",
  grant: %{
    program: "Clinical AI Benchmark",
    milestone: "Q2 Deliverable",
    run_number: 1
  },
  environment: %{
    elixir_version: "1.17.0",
    otp_version: "27.0",
    gpu: "NVIDIA RTX 4060 Ti",
    vram_gb: 16,
    quantization: "Q4_K_M"
  }
)

IO.puts("Started experiment: #{experiment.name}")
IO.puts("")

# 2. Insert simulated evaluation data
IO.puts("Inserting simulated evaluation data...")

# Simulate realistic MedQA results (61.2% accuracy)
correct_count = 780
total_count = 1273

for i <- 1..total_count do
  is_correct = i <= correct_count
  latency = 1000 + :rand.uniform(500)

  event = %{
    event_id: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
    event_name: [:medlum_llm, :eval, :sample, :stop],
    timestamp: System.system_time(:microsecond) + i,
    experiment_id: experiment.id,
    experiment_name: experiment.name,
    condition: experiment.condition,
    tags: experiment.tags,
    measurements: %{
      duration: latency * 1_000_000,
      input_tokens: 150,
      output_tokens: 25,
      tokens_per_second: 25.0
    },
    metadata: %{
      run_id: experiment.id,
      model: :biomistral_7b,
      sample_idx: i,
      sample_id: "medqa_#{String.pad_leading(Integer.to_string(i), 4, "0")}",
      predicted: if(is_correct, do: "A", else: "B"),
      correct_answer: "A",
      correct: is_correct
    },
    latency_ms: latency / 1.0,
    cost_usd: 0.0001,
    success: true
  }

  Store.insert(experiment.id, event)
end

IO.puts("  Inserted #{total_count} sample events")
IO.puts("")

# 3. Calculate metrics
IO.puts("Calculating metrics...")
{:ok, model_metrics} = Metrics.calculate_model_metrics(experiment.id)

biomistral = model_metrics[:biomistral_7b]
IO.puts("  BioMistral-7B:")
IO.puts("    Accuracy: #{Float.round(biomistral.accuracy, 3)}")
IO.puts("    Total samples: #{biomistral.total_samples}")
IO.puts("    Latency P95: #{biomistral.latency_p95 && Float.round(biomistral.latency_p95, 0)}ms")
IO.puts("")

# 4. Show published baselines
IO.puts("Published baselines for MedQA:")
baselines = Baselines.list_baselines("medqa")

baselines
|> Enum.take(5)
|> Enum.each(fn b ->
  IO.puts("  #{b.model}: #{Float.round(b.accuracy, 3)} (#{b.source})")
end)

IO.puts("")

# 5. Generate markdown report
IO.puts("Generating Markdown report...")
{:ok, markdown} = Reports.generate(experiment.id, :markdown,
  title: "Medical LLM Benchmark - Q2 Evaluation Results",
  include_environment: true,
  include_baselines: true
)

IO.puts("--- MARKDOWN REPORT ---")
IO.puts(markdown)
IO.puts("--- END REPORT ---\n")

# 6. Generate LaTeX report
IO.puts("Generating LaTeX report...")
{:ok, latex} = Reports.generate(experiment.id, :latex,
  title: "MedQA Zero-Shot Evaluation"
)

IO.puts("--- LATEX TABLE ---")
IO.puts(latex)
IO.puts("--- END LATEX ---\n")

# 7. Generate baseline comparison
IO.puts("Generating baseline comparison...")
{:ok, comparison} = Reports.baseline_comparison(experiment.id,
  dataset: "medqa"
)

IO.puts("--- BASELINE COMPARISON ---")
IO.puts(comparison)
IO.puts("--- END COMPARISON ---\n")

# 8. Generate JSON report
IO.puts("Generating JSON report...")
{:ok, json} = Reports.generate(experiment.id, :json,
  title: "MedQA Evaluation Results"
)

IO.puts("JSON report generated (#{byte_size(json)} bytes)")
IO.puts("")

# 9. Stop and cleanup
{:ok, _} = CrucibleTelemetry.stop_experiment(experiment.id)
CrucibleTelemetry.Experiment.cleanup(experiment.id)

IO.puts("Experiment cleaned up.")
IO.puts("\n=== Example Complete ===")
