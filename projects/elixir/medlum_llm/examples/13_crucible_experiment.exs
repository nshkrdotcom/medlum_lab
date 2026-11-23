#!/usr/bin/env elixir

# CrucibleHarness Medical Experiment Example
#
# This example demonstrates how to define and run medical AI benchmarks
# using CrucibleHarness for experiment orchestration.
#
# Prerequisites:
#   - Add {:crucible_harness, "~> 0.3"} to mix.exs dependencies
#   - Ollama running with medical LLMs
#
# Usage:
#   mix run examples/13_crucible_experiment.exs

Logger.configure(level: :warning)

# =============================================================================
# Define the Experiment Module
# =============================================================================

defmodule MedicalQAExperiment do
  @moduledoc """
  Example medical Q&A experiment comparing different LLMs.

  This demonstrates the correct CrucibleHarness DSL pattern:
  - `conditions` must be a list of maps with `:name` and `:fn` keys
  - `:fn` takes a single `sample` argument (the dataset item)
  - Each condition function returns a map with metric keys
  """

  use CrucibleHarness.Experiment

  name "Medical QA Model Comparison"
  description "Comparing BioMistral-7B and OpenBioLLM-8B on medical Q&A"
  author "MedlumLlm Team"
  version "1.0.0"

  # Dataset identifier - in a real scenario, this would reference
  # a registered dataset (e.g., :medqa, :pubmedqa)
  dataset :sample_medical_qa

  # Dataset configuration
  dataset_config %{
    sample_size: 10,        # Number of samples to evaluate
    split: "test"           # Dataset split
  }

  # Experimental conditions - each model is a condition
  # The `:fn` key must be a function that takes a single sample argument
  conditions [
    %{
      name: "biomistral_7b",
      fn: &__MODULE__.evaluate_biomistral/1
    },
    %{
      name: "openbio_8b",
      fn: &__MODULE__.evaluate_openbio/1
    }
  ]

  # Metrics to collect from condition function results
  # These must match keys in the maps returned by condition functions
  metrics [:accuracy, :latency_ms]

  # Number of times to repeat each sample (for statistical significance)
  repeat 3

  # Experiment configuration
  config %{
    execution_engine: :async_stream,  # Use streaming execution for GPU tasks
    max_parallel: 1,                   # One at a time for GPU-bound tasks
    timeout: 60_000,                   # 60s timeout per sample
    rate_limit: 10                     # Max 10 queries per second
  }

  # Statistical analysis parameters
  statistical_analysis %{
    significance_level: 0.05,
    confidence_interval: 0.95,
    multiple_testing_correction: :bonferroni
  }

  # Tags for organization
  tags [:medical, :qa, :benchmark, :llm_comparison]

  # =============================================================================
  # Condition Functions
  # =============================================================================

  @doc """
  Evaluates a sample using BioMistral-7B.

  This function:
  1. Receives a sample from the dataset
  2. Calls the LLM to generate a response
  3. Returns a map with metric values

  ## Sample Format

      %{
        id: "query_1",
        question: "What is the treatment for...",
        answer: "A",
        options: ["A", "B", "C", "D"]
      }

  ## Return Format

      %{
        prediction: "A",
        accuracy: 1.0 or 0.0,
        latency_ms: 1234
      }
  """
  def evaluate_biomistral(sample) do
    start_time = System.monotonic_time(:millisecond)

    # In production, this would call MedlumLlm.chat/2
    # For this example, we simulate the call
    prediction = simulate_llm_response(sample, :biomistral_7b)

    end_time = System.monotonic_time(:millisecond)
    latency_ms = end_time - start_time

    # Calculate accuracy (1.0 if correct, 0.0 if incorrect)
    accuracy = if prediction == sample.answer, do: 1.0, else: 0.0

    %{
      prediction: prediction,
      accuracy: accuracy,
      latency_ms: latency_ms
    }
  end

  @doc """
  Evaluates a sample using OpenBioLLM-8B.
  """
  def evaluate_openbio(sample) do
    start_time = System.monotonic_time(:millisecond)

    prediction = simulate_llm_response(sample, :openbio_8b)

    end_time = System.monotonic_time(:millisecond)
    latency_ms = end_time - start_time

    accuracy = if prediction == sample.answer, do: 1.0, else: 0.0

    %{
      prediction: prediction,
      accuracy: accuracy,
      latency_ms: latency_ms
    }
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp simulate_llm_response(sample, model) do
    # Simulated LLM response for demonstration
    # In production, use:
    #   {:ok, response} = MedlumLlm.chat(prompt, model: model)
    #   parse_mcq_response(response)

    # Add some simulated latency
    Process.sleep(100 + :rand.uniform(200))

    # Simulate different accuracy per model
    case model do
      :biomistral_7b ->
        if :rand.uniform() < 0.75, do: sample.answer, else: random_option()

      :openbio_8b ->
        if :rand.uniform() < 0.80, do: sample.answer, else: random_option()
    end
  end

  defp random_option do
    Enum.random(["A", "B", "C", "D"])
  end
end

# =============================================================================
# Run the Experiment
# =============================================================================

IO.puts("""
╔═══════════════════════════════════════════════════════════════════╗
║           CrucibleHarness Medical Experiment Example              ║
╚═══════════════════════════════════════════════════════════════════╝

This example demonstrates how to define medical AI experiments using
the CrucibleHarness DSL.

Key concepts:
  - `conditions` is a list of maps with `:name` and `:fn` keys
  - Each condition `:fn` takes a single sample argument
  - Condition functions return maps with metric keys
  - CrucibleHarness handles orchestration, checkpointing, and stats

""")

# Verify CrucibleHarness is available
unless Code.ensure_loaded?(CrucibleHarness) do
  IO.puts("""
  ⚠️  CrucibleHarness not found in dependencies.

  To run this example, add to mix.exs:

      {:crucible_harness, "~> 0.3"}

  Or run a simulated version without CrucibleHarness:
  """)

  # Run simulated experiment
  IO.puts("\n📊 Running simulated experiment...\n")

  config = MedicalQAExperiment.__config__()

  IO.puts("Experiment: #{config.name}")
  IO.puts("Conditions: #{Enum.map(config.conditions, & &1.name) |> Enum.join(", ")}")
  IO.puts("Metrics: #{Enum.join(config.metrics, ", ")}")
  IO.puts("Repeats: #{config.repeat}")
  IO.puts("")

  # Simulate running a few samples
  samples = [
    %{id: "q1", question: "What is the first-line treatment for hypertension?", answer: "A"},
    %{id: "q2", question: "Which medication is contraindicated in pregnancy?", answer: "B"},
    %{id: "q3", question: "What is the mechanism of action of metformin?", answer: "C"}
  ]

  IO.puts("Running #{length(samples)} samples × #{length(config.conditions)} conditions × #{config.repeat} repeats...")
  IO.puts("")

  results =
    for condition <- config.conditions,
        sample <- samples do
      result = condition.fn.(sample)
      IO.puts("  ✓ #{condition.name} | #{sample.id} | acc=#{result.accuracy} | #{result.latency_ms}ms")
      {condition.name, result}
    end

  # Calculate per-condition accuracy
  IO.puts("\n📈 Results Summary:\n")

  for {condition_name, condition_results} <- Enum.group_by(results, &elem(&1, 0), &elem(&1, 1)) do
    accuracies = Enum.map(condition_results, & &1.accuracy)
    mean_acc = Enum.sum(accuracies) / length(accuracies)
    latencies = Enum.map(condition_results, & &1.latency_ms)
    mean_lat = Enum.sum(latencies) / length(latencies)

    IO.puts("  #{condition_name}:")
    IO.puts("    Accuracy: #{Float.round(mean_acc * 100, 1)}%")
    IO.puts("    Mean Latency: #{Float.round(mean_lat, 1)}ms")
  end

  System.halt(0)
end

# With CrucibleHarness available, run the full experiment
IO.puts("📊 Running experiment with CrucibleHarness...\n")

case CrucibleHarness.run(MedicalQAExperiment,
       output_dir: "./results/medical_qa",
       formats: [:markdown],
       confirm: false
     ) do
  {:ok, report} ->
    IO.puts("✅ Experiment completed successfully!")
    IO.puts("   Experiment ID: #{report.experiment_id}")
    IO.puts("   Results: #{length(report.results)} samples")
    IO.puts("   Reports: #{inspect(Map.keys(report.reports))}")

  {:error, reason} ->
    IO.puts("❌ Experiment failed: #{inspect(reason)}")
end
