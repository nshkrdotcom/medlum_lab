#!/usr/bin/env elixir

# CrucibleHarness Medical Experiment Templates
#
# This file provides reusable experiment templates for common
# medical AI evaluation tasks. These templates demonstrate the
# correct CrucibleHarness DSL patterns.
#
# Usage:
#   - Copy and customize these templates for your experiments
#   - Ensure CrucibleHarness is added as a dependency
#
# Key Pattern:
#   conditions [
#     %{name: "model_name", fn: &function/1}
#   ]
#
# The condition `:fn` always takes a single sample argument.

Logger.configure(level: :warning)

IO.puts("""
╔═══════════════════════════════════════════════════════════════════╗
║           CrucibleHarness Medical Experiment Templates            ║
╚═══════════════════════════════════════════════════════════════════╝
""")

# =============================================================================
# Template 1: Multiple Choice Q&A Benchmark
# =============================================================================

defmodule Templates.MCQBenchmark do
  @moduledoc """
  Template for multiple-choice medical Q&A benchmarks (MedQA, MedMCQA, etc.)

  ## Dataset Sample Format

      %{
        id: "sample_123",
        question: "Which of the following is the first-line treatment...",
        options: ["A. Drug X", "B. Drug Y", "C. Drug Z", "D. Observation"],
        answer: "A"
      }

  ## Usage

      defmodule MyMedQAExperiment do
        use CrucibleHarness.Experiment

        name "MedQA Zero-Shot Comparison"
        dataset :medqa

        conditions [
          %{name: "biomistral_7b", fn: &evaluate_model(&1, :biomistral_7b)},
          %{name: "openbio_8b", fn: &evaluate_model(&1, :openbio_8b)}
        ]

        metrics [:accuracy, :latency_ms]

        defp evaluate_model(sample, model_id) do
          # Implementation
        end
      end
  """

  use CrucibleHarness.Experiment

  name "MCQ Benchmark Template"
  description "Template for medical multiple-choice question benchmarks"
  dataset :medqa

  dataset_config %{
    sample_size: 100,
    split: "test"
  }

  conditions [
    %{
      name: "biomistral_7b",
      fn: fn sample ->
        # Build zero-shot prompt
        prompt = build_mcq_prompt(sample)

        # Call LLM and measure latency
        {latency_ms, prediction} = timed_inference(prompt, :biomistral_7b)

        # Calculate accuracy
        accuracy = if prediction == sample.answer, do: 1.0, else: 0.0

        %{
          prediction: prediction,
          accuracy: accuracy,
          latency_ms: latency_ms
        }
      end
    },
    %{
      name: "openbio_8b",
      fn: fn sample ->
        prompt = build_mcq_prompt(sample)
        {latency_ms, prediction} = timed_inference(prompt, :openbio_8b)
        accuracy = if prediction == sample.answer, do: 1.0, else: 0.0

        %{
          prediction: prediction,
          accuracy: accuracy,
          latency_ms: latency_ms
        }
      end
    }
  ]

  metrics [:accuracy, :latency_ms]
  repeat 1

  config %{
    execution_engine: :async_stream,
    max_parallel: 1,
    timeout: 120_000
  }

  # Helper functions must be defined outside the conditions list
  def build_mcq_prompt(sample) do
    """
    Question: #{sample.question}

    Options:
    #{Enum.join(sample.options, "\n")}

    Answer with only the letter (A, B, C, or D):
    """
  end

  def timed_inference(prompt, model_id) do
    start = System.monotonic_time(:millisecond)

    # In production: {:ok, response} = MedlumLlm.chat(prompt, model: model_id)
    # Simulated for demonstration:
    Process.sleep(100)
    prediction = Enum.random(["A", "B", "C", "D"])

    elapsed = System.monotonic_time(:millisecond) - start
    {elapsed, prediction}
  end
end

# =============================================================================
# Template 2: Clinical Summarization Benchmark
# =============================================================================

defmodule Templates.SummarizationBenchmark do
  @moduledoc """
  Template for clinical text summarization benchmarks.

  ## Dataset Sample Format

      %{
        id: "note_456",
        source_text: "Patient presents with chest pain...",
        reference_summary: "55yo male with ACS..."
      }

  ## Metrics

  - rouge_1: ROUGE-1 F1 score
  - rouge_2: ROUGE-2 F1 score
  - rouge_l: ROUGE-L F1 score
  - latency_ms: Inference latency
  - hallucination_score: CVL verification score (if using CVL)
  """

  use CrucibleHarness.Experiment

  name "Clinical Summarization Template"
  dataset :clinical_notes

  dataset_config %{
    sample_size: 50,
    max_source_length: 2048
  }

  conditions [
    %{
      name: "biomistral_7b",
      fn: fn sample ->
        prompt = """
        Summarize the following clinical note in 2-3 sentences.
        Focus on: diagnosis, key findings, and recommended actions.

        Clinical Note:
        #{sample.source_text}

        Summary:
        """

        start = System.monotonic_time(:millisecond)
        # {:ok, generated} = MedlumLlm.chat(prompt, model: :biomistral_7b)
        generated = "[Simulated summary of clinical note]"
        elapsed = System.monotonic_time(:millisecond) - start

        # Calculate ROUGE scores (would use eval_ex in production)
        rouge_scores = calculate_rouge(generated, sample.reference_summary)

        %{
          generated_summary: generated,
          rouge_1: rouge_scores.rouge_1,
          rouge_2: rouge_scores.rouge_2,
          rouge_l: rouge_scores.rouge_l,
          latency_ms: elapsed
        }
      end
    }
  ]

  metrics [:rouge_1, :rouge_2, :rouge_l, :latency_ms]
  repeat 1

  config %{
    execution_engine: :async_stream,
    max_parallel: 1,
    timeout: 180_000
  }

  def calculate_rouge(_generated, _reference) do
    # In production, use EvalEx or similar:
    # EvalEx.Metrics.rouge(generated, reference)
    %{rouge_1: 0.45, rouge_2: 0.23, rouge_l: 0.40}
  end
end

# =============================================================================
# Template 3: CVL Hallucination Detection Benchmark
# =============================================================================

defmodule Templates.HallucinationBenchmark do
  @moduledoc """
  Template for evaluating Clinical Verification Layer (CVL) performance.

  ## Dataset Sample Format

      %{
        id: "claim_789",
        claim: "Patient was prescribed 500mg metformin BID",
        source_documents: ["Clinical note 1...", "Clinical note 2..."],
        ground_truth: :entailment  # :entailment | :contradiction | :neutral
      }

  ## Metrics

  - accuracy: Overall classification accuracy
  - precision: Precision for hallucination detection
  - recall: Recall for hallucination detection
  - f1: F1 score for hallucination detection
  """

  use CrucibleHarness.Experiment

  name "CVL Hallucination Detection Template"
  dataset :cvl_evaluation

  dataset_config %{
    sample_size: 200,
    include_hard_negatives: true
  }

  conditions [
    %{
      name: "cvl_multi_agent",
      fn: fn sample ->
        start = System.monotonic_time(:millisecond)

        # Run CVL verification
        # {:ok, result} = MedlumLlm.CVL.Verifier.verify_claim(
        #   sample.claim,
        #   sample.source_documents
        # )
        predicted_verdict = Enum.random([:entailment, :contradiction, :neutral])

        elapsed = System.monotonic_time(:millisecond) - start

        # Compare to ground truth
        correct = predicted_verdict == sample.ground_truth
        is_hallucination_detected = predicted_verdict in [:contradiction, :neutral]
        actual_hallucination = sample.ground_truth in [:contradiction, :neutral]

        %{
          predicted_verdict: predicted_verdict,
          correct: if(correct, do: 1.0, else: 0.0),
          true_positive: if(is_hallucination_detected and actual_hallucination, do: 1.0, else: 0.0),
          false_positive: if(is_hallucination_detected and not actual_hallucination, do: 1.0, else: 0.0),
          false_negative: if(not is_hallucination_detected and actual_hallucination, do: 1.0, else: 0.0),
          latency_ms: elapsed
        }
      end
    }
  ]

  metrics [:correct, :true_positive, :false_positive, :false_negative, :latency_ms]
  repeat 1

  config %{
    execution_engine: :async_stream,
    max_parallel: 2,  # CVL can run multiple verifications in parallel
    timeout: 60_000
  }
end

# =============================================================================
# Template 4: Streaming Large Dataset Benchmark
# =============================================================================

defmodule Templates.StreamingBenchmark do
  @moduledoc """
  Template for benchmarks on large datasets using streaming execution.

  This template demonstrates:
  - Using `:async_stream` execution engine
  - Handling datasets that don't fit in memory
  - Configuring bounded concurrency for GPU tasks
  """

  use CrucibleHarness.Experiment

  name "Large Dataset Streaming Template"
  dataset :large_medical_corpus

  dataset_config %{
    sample_size: 10_000,    # Large dataset
    limit: 1000,            # Process only first 1000 for quick runs
    streaming: true
  }

  conditions [
    %{
      name: "biomistral_7b",
      fn: fn sample ->
        # Minimal processing for throughput testing
        start = System.monotonic_time(:millisecond)

        # Process sample
        Process.sleep(50)  # Simulated inference

        elapsed = System.monotonic_time(:millisecond) - start

        %{
          processed: 1.0,
          latency_ms: elapsed
        }
      end
    }
  ]

  metrics [:processed, :latency_ms]
  repeat 1

  config %{
    execution_engine: :async_stream,  # CRITICAL: Use streaming for large datasets
    max_parallel: 4,                   # Bounded concurrency
    timeout: 30_000
    # Note: No checkpoint_interval needed - async_stream handles this
  }
end

# =============================================================================
# Display Templates
# =============================================================================

templates = [
  {Templates.MCQBenchmark, "Multiple Choice Q&A (MedQA, MedMCQA)"},
  {Templates.SummarizationBenchmark, "Clinical Summarization"},
  {Templates.HallucinationBenchmark, "CVL Hallucination Detection"},
  {Templates.StreamingBenchmark, "Large Dataset Streaming"}
]

IO.puts("Available Templates:\n")

for {module, description} <- templates do
  config = module.__config__()

  IO.puts("📋 #{description}")
  IO.puts("   Module: #{inspect(module)}")
  IO.puts("   Conditions: #{length(config.conditions)}")
  IO.puts("   Metrics: #{Enum.join(config.metrics, ", ")}")
  IO.puts("   Engine: #{config.config[:execution_engine] || :flow}")
  IO.puts("")
end

IO.puts("""
Usage Pattern:
═════════════

1. Copy the template module to your project
2. Customize:
   - Dataset reference and config
   - Condition functions (call MedlumLlm.chat/2, MedlumLlm.embed/2, etc.)
   - Metrics to collect
3. Run with CrucibleHarness:

   {:ok, report} = CrucibleHarness.run(MyExperiment,
     output_dir: "./results",
     formats: [:markdown, :html]
   )

Key DSL Rules:
══════════════

✓ conditions must be a list of %{name: string, fn: fn(sample) -> map()}
✓ Each fn returns a map with keys matching the metrics list
✓ Use :async_stream engine for GPU-bound or large datasets
✓ Statistical tests (Wilson CI, McNemar) live in crucible_bench, not here
""")
