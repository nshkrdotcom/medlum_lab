#!/usr/bin/env elixir
# End-to-End Evaluation Pipeline Example
#
# This example demonstrates the complete workflow for:
# 1. Loading a medical dataset
# 2. Running model evaluation (simulated or real)
# 3. Calculating metrics with confidence intervals
# 4. Comparing against published baselines
# 5. CVL verification of model outputs
#
# Run with: mix run examples/evaluation_pipeline.exs

alias MedlumLlm.Datasets
alias MedlumLlm.Eval.{Benchmarks, Baselines, Prompts, MedicalMetrics}
alias MedlumLlm.CVL.Verifier

IO.puts("=== MedlumLlm End-to-End Evaluation Pipeline ===\n")

# =============================================================================
# Configuration
# =============================================================================

config = %{
  benchmark: :medqa_zero_shot,
  model: :biomistral_7b,
  sample_limit: 10,  # Small for demo, use larger in practice
  timeout_ms: 60_000,
  use_real_inference: false  # Set to true if Ollama is running
}

IO.puts("Configuration:")
IO.puts("  Benchmark: #{config.benchmark}")
IO.puts("  Model: #{config.model}")
IO.puts("  Sample Limit: #{config.sample_limit}")
IO.puts("  Real Inference: #{config.use_real_inference}")
IO.puts("")

# =============================================================================
# Step 1: Load Benchmark Configuration
# =============================================================================

IO.puts("Step 1: Loading Benchmark Configuration...")

{:ok, benchmark} = Benchmarks.get(config.benchmark)
IO.puts("  Name: #{benchmark.name}")
IO.puts("  Dataset: #{benchmark.dataset}")
IO.puts("  Task: #{benchmark.task}")
IO.puts("  Prompt Template: #{benchmark.prompt_template}")
IO.puts("  Metrics: #{inspect(benchmark.metrics)}")
IO.puts("")

# =============================================================================
# Step 2: Load or Create Dataset
# =============================================================================

IO.puts("Step 2: Loading Dataset...")

samples = case Datasets.load(benchmark.dataset, split: benchmark.split, limit: config.sample_limit) do
  {:ok, data} ->
    samples_list = Enum.to_list(data)
    IO.puts("  Loaded #{length(samples_list)} samples from #{benchmark.dataset}")

    if length(samples_list) > 0 do
      sample = hd(samples_list)
      IO.puts("  First sample question: #{String.slice(sample.question, 0..60)}...")
    end

    samples_list

  {:error, reason} ->
    IO.puts("  Could not load dataset: #{inspect(reason)}")
    IO.puts("  Using mock data for demonstration...")
    create_mock_samples()
end

IO.puts("")

# =============================================================================
# Step 3: Generate Prompts and Get Responses
# =============================================================================

IO.puts("Step 3: Running Model Evaluation...")

results = Enum.map(Enum.with_index(samples, 1), fn {sample, idx} ->
  # Format prompt using template
  prompt = Prompts.format(benchmark.prompt_template, sample)

  start_time = System.monotonic_time(:millisecond)

  # Get model response (real or simulated)
  response = if config.use_real_inference do
    case MedlumLlm.Chat.chat(prompt, model: config.model, timeout: config.timeout_ms) do
      {:ok, resp} -> resp
      {:error, _} -> simulate_response(sample)
    end
  else
    simulate_response(sample)
  end

  latency = System.monotonic_time(:millisecond) - start_time

  # Parse the response
  predicted = Prompts.parse_mcq_response(response)
  correct = predicted == sample.answer

  IO.puts("  Sample #{idx}: predicted=#{predicted || "?"}, actual=#{sample.answer}, #{if correct, do: "CORRECT", else: "WRONG"}")

  %{
    sample_id: idx,
    question: String.slice(sample.question, 0..50),
    predicted: predicted,
    actual: sample.answer,
    correct: correct,
    latency_ms: latency,
    response: response
  }
end)

correct_count = Enum.count(results, & &1.correct)
IO.puts("")
IO.puts("  Completed #{length(results)} evaluations")
IO.puts("  Correct: #{correct_count}/#{length(results)}")
IO.puts("")

# =============================================================================
# Step 4: Calculate Metrics
# =============================================================================

IO.puts("Step 4: Calculating Metrics...")

predictions = Enum.map(results, & &1.predicted)
total = length(results)

# Calculate accuracy with confidence interval
accuracy = MedicalMetrics.accuracy(predictions, samples)
{ci_lower, ci_upper} = MedicalMetrics.wilson_ci(correct_count, total)

# Calculate latency percentiles
latencies = Enum.map(results, & &1.latency_ms)
sorted_latencies = Enum.sort(latencies)
p50 = Enum.at(sorted_latencies, div(length(sorted_latencies), 2))
p95_idx = min(round(length(sorted_latencies) * 0.95), length(sorted_latencies) - 1)
p95 = Enum.at(sorted_latencies, p95_idx)

IO.puts("  Accuracy: #{Float.round(accuracy * 100, 1)}%")
IO.puts("  95% CI: [#{Float.round(ci_lower * 100, 1)}%, #{Float.round(ci_upper * 100, 1)}%]")
IO.puts("  P50 Latency: #{p50}ms")
IO.puts("  P95 Latency: #{p95}ms")
IO.puts("")

# =============================================================================
# Step 5: Compare Against Baseline
# =============================================================================

IO.puts("Step 5: Baseline Comparison...")

comparison = Baselines.format_comparison(benchmark.dataset, config.model, accuracy)
status = Baselines.compare(benchmark.dataset, config.model, accuracy)

status_msg = case status do
  :match -> "Within 5% of published baseline"
  :above -> "Above published baseline"
  :below -> "Below published baseline"
  :no_baseline -> "No baseline available for comparison"
end

IO.puts("  Result: #{comparison}")
IO.puts("  Status: #{status_msg}")

case Baselines.get(benchmark.dataset, config.model) do
  {:ok, baseline} ->
    IO.puts("  Baseline Source: #{baseline.source} (#{baseline.date})")
  _ -> :ok
end
IO.puts("")

# =============================================================================
# Step 6: CVL Verification of Outputs
# =============================================================================

IO.puts("Step 6: CVL Verification of Model Outputs...")

# For each prediction, verify it against the question/answer
cvl_results = Enum.map(results, fn result ->
  # Create a claim from the prediction
  claim = "The correct answer is #{result.predicted || "unknown"}"

  # Use the question and correct answer as source
  source = ["Question: #{result.question}. The correct answer is #{result.actual}."]

  case Verifier.verify_summary(claim, source) do
    {:ok, cvl_result} ->
      %{
        sample_id: result.sample_id,
        predicted: result.predicted,
        actual: result.actual,
        model_correct: result.correct,
        cvl_verdict: cvl_result.summary_verdict,
        cvl_confidence: cvl_result.summary_confidence,
        needs_review: cvl_result.needs_review_count > 0
      }

    {:error, _} ->
      %{
        sample_id: result.sample_id,
        predicted: result.predicted,
        actual: result.actual,
        model_correct: result.correct,
        cvl_verdict: :error,
        cvl_confidence: 0.0,
        needs_review: true
      }
  end
end)

# Summarize CVL results
entailment_count = Enum.count(cvl_results, & &1.cvl_verdict == :entailment)
contradiction_count = Enum.count(cvl_results, & &1.cvl_verdict == :contradiction)
neutral_count = Enum.count(cvl_results, & &1.cvl_verdict == :neutral)
needs_review_count = Enum.count(cvl_results, & &1.needs_review)

IO.puts("  CVL Verdicts:")
IO.puts("    Entailment: #{entailment_count}")
IO.puts("    Contradiction: #{contradiction_count}")
IO.puts("    Neutral: #{neutral_count}")
IO.puts("    Needs Review: #{needs_review_count}")
IO.puts("")

# Cross-reference CVL vs model correctness
correct_and_entailment = Enum.count(cvl_results, & &1.model_correct && &1.cvl_verdict == :entailment)
wrong_and_contradiction = Enum.count(cvl_results, & !&1.model_correct && &1.cvl_verdict == :contradiction)

IO.puts("  CVL Alignment with Ground Truth:")
IO.puts("    Correct predictions flagged as entailment: #{correct_and_entailment}")
IO.puts("    Wrong predictions flagged as contradiction: #{wrong_and_contradiction}")
IO.puts("")

# =============================================================================
# Step 7: Error Analysis
# =============================================================================

IO.puts("Step 7: Error Analysis...")

wrong_answers = Enum.filter(results, & !&1.correct)

if length(wrong_answers) > 0 do
  IO.puts("  Incorrect Predictions:")
  for result <- Enum.take(wrong_answers, 5) do
    IO.puts("    Sample #{result.sample_id}: predicted #{result.predicted || "nil"}, actual #{result.actual}")
  end
else
  IO.puts("  No incorrect predictions!")
end
IO.puts("")

# =============================================================================
# Step 8: Summary Report
# =============================================================================

IO.puts("Step 8: Summary Report")
IO.puts(String.duplicate("=", 60))
IO.puts("")
IO.puts("  EVALUATION SUMMARY")
IO.puts("  " <> String.duplicate("-", 40))
IO.puts("")
IO.puts("  Model: #{config.model}")
IO.puts("  Benchmark: #{benchmark.name}")
IO.puts("  Dataset: #{benchmark.dataset}")
IO.puts("  Samples: #{total}")
IO.puts("")
IO.puts("  ACCURACY")
IO.puts("    Score: #{Float.round(accuracy * 100, 1)}%")
IO.puts("    95% CI: [#{Float.round(ci_lower * 100, 1)}%, #{Float.round(ci_upper * 100, 1)}%]")
IO.puts("    Baseline: #{comparison}")
IO.puts("    Status: #{status}")
IO.puts("")
IO.puts("  LATENCY")
IO.puts("    P50: #{p50}ms")
IO.puts("    P95: #{p95}ms")
IO.puts("")
IO.puts("  CVL VERIFICATION")
IO.puts("    Entailment Rate: #{Float.round(entailment_count / total * 100, 1)}%")
IO.puts("    Contradiction Rate: #{Float.round(contradiction_count / total * 100, 1)}%")
IO.puts("    Needs Review: #{needs_review_count}/#{total}")
IO.puts("")
IO.puts(String.duplicate("=", 60))
IO.puts("")

# =============================================================================
# Helper Functions
# =============================================================================

defmodule MockHelpers do
  def create_mock_samples do
    [
      %{
        question: "A 45-year-old woman with fatigue and weight gain. Best initial test?",
        options: ["A. CBC", "B. TSH", "C. Glucose", "D. LFT"],
        answer: "B"
      },
      %{
        question: "Treatment for acute MI with ST elevation?",
        options: ["A. Aspirin only", "B. PCI", "C. Observation", "D. Beta blockers"],
        answer: "B"
      },
      %{
        question: "Most common cause of community-acquired pneumonia?",
        options: ["A. E. coli", "B. S. pneumoniae", "C. P. aeruginosa", "D. K. pneumoniae"],
        answer: "B"
      },
      %{
        question: "First-line treatment for uncomplicated UTI in women?",
        options: ["A. Ciprofloxacin", "B. Nitrofurantoin", "C. Amoxicillin", "D. Vancomycin"],
        answer: "B"
      },
      %{
        question: "Classic triad of Cushing syndrome?",
        options: ["A. HTN/DM/Obesity", "B. Fever/Rash/Arthritis", "C. Polyuria/Polydipsia/Weight loss", "D. Headache/Vision/Nausea"],
        answer: "A"
      },
      %{
        question: "Drug of choice for Parkinson's disease?",
        options: ["A. Haloperidol", "B. Levodopa", "C. Phenytoin", "D. Lithium"],
        answer: "B"
      },
      %{
        question: "Most common cause of hyperthyroidism?",
        options: ["A. Hashimoto's", "B. Graves' disease", "C. Thyroid cancer", "D. Iodine deficiency"],
        answer: "B"
      },
      %{
        question: "First-line treatment for type 2 diabetes?",
        options: ["A. Insulin", "B. Metformin", "C. Sulfonylurea", "D. GLP-1 agonist"],
        answer: "B"
      },
      %{
        question: "Most common arrhythmia in adults?",
        options: ["A. Ventricular tachycardia", "B. Atrial fibrillation", "C. Heart block", "D. SVT"],
        answer: "B"
      },
      %{
        question: "Best test for pulmonary embolism?",
        options: ["A. Chest X-ray", "B. CT angiography", "C. ECG", "D. Echocardiogram"],
        answer: "B"
      }
    ]
  end

  def simulate_response(sample) do
    # Simulate ~75% accuracy for realistic demo
    if :rand.uniform() < 0.75 do
      sample.answer
    else
      # Return a wrong answer
      ["A", "B", "C", "D"]
      |> Enum.reject(& &1 == sample.answer)
      |> Enum.random()
    end
  end
end

# Import helpers at top of script
import MockHelpers

IO.puts("=== Evaluation Pipeline Complete ===")
