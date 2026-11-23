# Medical Telemetry Guide

This guide covers the `MedlumLlm.Telemetry` namespace for medical AI evaluation.

## Overview

The medical telemetry extensions provide specialized telemetry functionality for MedlumLlm and
related medical NLP applications:

- **Events**: 16 medical-specific telemetry events
- **Metrics**: CVL accuracy, hallucination detection, model metrics with CI
- **Experiment**: Standardized metadata for medical evaluations
- **Reports**: Grant-ready Markdown, LaTeX, HTML, and JSON reports
- **Baselines**: Published baseline results for comparison

## Architecture

```
MedlumLlm.Telemetry
├── Events      # Medical event definitions ([:medlum_llm, ...])
├── Metrics     # CVL and model metrics calculation
├── Experiment  # Medical experiment helpers
├── Reports     # Grant-ready report generation
└── Baselines   # Published baseline results
```

## Event Schema

Medical events follow the telemetry convention: `[:medlum_llm, domain, action, phase]`

### Evaluation Events

Track benchmark runs and sample evaluations:

```elixir
# Run lifecycle
[:medlum_llm, :eval, :run, :start]
[:medlum_llm, :eval, :run, :stop]

# Sample evaluation
[:medlum_llm, :eval, :sample, :start]
[:medlum_llm, :eval, :sample, :stop]
[:medlum_llm, :eval, :sample, :exception]
```

#### Sample Stop Event Schema

```elixir
[:medlum_llm, :eval, :sample, :stop]
measurements: %{
  duration: integer(),           # nanoseconds
  input_tokens: integer(),
  output_tokens: integer(),
  tokens_per_second: float()
}
metadata: %{
  run_id: String.t(),
  model: atom(),
  sample_idx: integer(),
  sample_id: String.t() | nil,
  predicted: String.t(),
  correct_answer: String.t(),
  correct: boolean(),
  cost_usd: float() | nil
}
```

### CVL Events

Track Clinical Verification Layer hallucination detection:

```elixir
# Verification lifecycle
[:medlum_llm, :cvl, :verification, :start]
[:medlum_llm, :cvl, :verification, :stop]

# Individual agents
[:medlum_llm, :cvl, :agent, :medication, :stop]  # RxNorm
[:medlum_llm, :cvl, :agent, :lab, :stop]         # LOINC
[:medlum_llm, :cvl, :agent, :ontology, :stop]    # SNOMED-CT/ICD-10
[:medlum_llm, :cvl, :agent, :temporal, :stop]    # Timeline consistency
[:medlum_llm, :cvl, :agent, :differential, :stop] # Differential diagnosis
```

#### Verification Stop Event Schema

```elixir
[:medlum_llm, :cvl, :verification, :stop]
measurements: %{
  duration: integer(),           # nanoseconds
  agent_calls: integer()
}
metadata: %{
  verification_id: String.t(),
  verdict: :entailment | :contradiction | :neutral,
  confidence: float(),           # 0.0-1.0
  hallucination_detected: boolean(),
  agents: %{
    medication: %{verdict: atom(), confidence: float(), latency_ms: float()},
    lab: %{verdict: atom(), confidence: float(), latency_ms: float()},
    ontology: %{verdict: atom(), confidence: float(), latency_ms: float()},
    temporal: %{verdict: atom(), confidence: float(), latency_ms: float()},
    differential: %{verdict: atom(), confidence: float(), latency_ms: float()}
  },
  disagreement_count: integer(),
  consensus_method: atom()
}
```

### Document Events

Track clinical document processing:

```elixir
[:medlum_llm, :document, :process, :start]
[:medlum_llm, :document, :process, :stop]
[:medlum_llm, :document, :summarize, :stop]
[:medlum_llm, :document, :extract, :stop]
```

## Starting a Medical Evaluation

Use `MedlumLlm.Telemetry.Experiment` for standardized experiment setup:

```elixir
alias MedlumLlm.Telemetry.Experiment

{:ok, exp} = Experiment.start_evaluation("medqa_biomistral_20260125",
  # Benchmark configuration
  benchmark: :medqa_zero_shot,
  models: [:biomistral_7b, :openbio_8b],
  seed: 42,

  # Scientific context
  hypothesis: "BioMistral-7B achieves >70% on MedQA zero-shot",

  # Dataset pinning
  dataset: %{
    name: "medqa",
    split: "test",
    revision: "abc123def456"
  },

  # Evaluation context (optional)
  grant: %{
    program: "Clinical AI Benchmark",
    milestone: "Q2 Deliverable"
  }
)

# Experiment includes auto-generated tags
exp.tags
# => ["evaluation", "medqa_zero_shot", "biomistral_7b", "openbio_8b"]
```

### Environment Fingerprinting

When `CrucibleBench` is available, environment is auto-captured:

```elixir
exp.metadata.environment
# => %{
#      elixir_version: "1.17.0",
#      otp_version: "27.0",
#      gpu: "NVIDIA RTX 4060 Ti",
#      vram_gb: 16,
#      ...
#    }
```

You can also provide a pre-captured environment:

```elixir
env = CrucibleBench.Environment.capture()

{:ok, exp} = Experiment.start_evaluation("my_eval",
  benchmark: :medqa,
  models: [:test_model],
  environment: env
)
```

## Emitting Events

Your evaluation code emits standard telemetry events:

```elixir
defmodule MyEvaluator do
  def evaluate_sample(experiment_id, model, sample, idx) do
    start_time = System.monotonic_time()

    # Emit start event
    :telemetry.execute(
      [:medlum_llm, :eval, :sample, :start],
      %{system_time: System.system_time()},
      %{run_id: experiment_id, model: model, sample_idx: idx}
    )

    # Run inference
    result = run_model(model, sample)
    duration = System.monotonic_time() - start_time

    # Emit stop event
    :telemetry.execute(
      [:medlum_llm, :eval, :sample, :stop],
      %{
        duration: System.convert_time_unit(duration, :native, :nanosecond),
        input_tokens: result.input_tokens,
        output_tokens: result.output_tokens,
        tokens_per_second: result.tps
      },
      %{
        run_id: experiment_id,
        model: model,
        sample_idx: idx,
        predicted: result.answer,
        correct_answer: sample.correct_answer,
        correct: result.answer == sample.correct_answer,
        cost_usd: result.cost
      }
    )
  end
end
```

## Calculating Metrics

### Model Metrics

```elixir
alias MedlumLlm.Telemetry.Metrics

{:ok, model_metrics} = Metrics.calculate_model_metrics(experiment_id)

model_metrics[:biomistral_7b]
# => %{
#      model: :biomistral_7b,
#      accuracy: 0.612,
#      accuracy_ci_lower: 0.583,     # Wilson score CI (via CrucibleBench)
#      accuracy_ci_upper: 0.640,
#      total_samples: 1273,
#      correct: 779,
#      errors: 5,
#      latency_p50: 1180.0,
#      latency_p95: 2400.0,
#      tokens_per_second: 25.5
#    }
```

### CVL Metrics

```elixir
{:ok, cvl_metrics} = Metrics.calculate_cvl_metrics(experiment_id)

cvl_metrics
# => %{
#      cvl_accuracy: 0.87,
#      hallucination_precision: 0.91,
#      hallucination_recall: 0.94,
#      hallucination_f1: 0.925,
#      agent_agreement_rate: 0.82,
#      mean_verification_latency_ms: 450.0,
#      total_verifications: 500,
#      entailment_count: 435,
#      contradiction_count: 40,
#      neutral_count: 25
#    }
```

## Generating Reports

### Markdown Report

```elixir
alias MedlumLlm.Telemetry.Reports

{:ok, markdown} = Reports.generate(experiment_id, :markdown,
  title: "Medical LLM Benchmark - Q2 Evaluation Results",
  include_environment: true,
  include_baselines: true,
  confidence_level: 0.95
)

File.write!("reports/q2_report.md", markdown)
```

Output:

```markdown
# Medical LLM Benchmark - Q2 Evaluation Results

Generated: 2026-01-25T10:30:00Z

## Summary

| Experiment | Model | Accuracy | 95% CI | Latency P95 | Samples |
|------------|-------|----------|--------|-------------|---------|
| medqa_biomistral | biomistral_7b | 0.612 | [0.583, 0.640] | 2400ms | 1273 |

## Environment

- **Elixir Version**: 1.17.0
- **OTP Version**: 27.0
- **GPU**: NVIDIA RTX 4060 Ti

## Published Baselines (medqa)

| Model | Accuracy | Source |
|-------|----------|--------|
| GPT-4 | 0.861 | OpenAI 2023 |
| Med-PaLM 2 | 0.867 | Google 2023 |
```

### LaTeX Report

```elixir
{:ok, latex} = Reports.generate(experiment_id, :latex,
  title: "Medical LLM Evaluation"
)
```

Output:

```latex
\begin{table}[h]
\centering
\caption{Medical LLM Evaluation}
\begin{tabular}{lrrr}
\toprule
Model & Accuracy & 95\% CI & P95 Latency \\
\midrule
biomistral_7b & 0.612 & [0.583, 0.640] & 2400ms \\
\bottomrule
\end{tabular}
\label{tab:eval_results}
\end{table}
```

### Comparison Tables

Compare multiple experiments:

```elixir
{:ok, table} = Reports.comparison_table(
  [control_id, treatment_id],
  :markdown,
  title: "A/B Test Results"
)
```

### Baseline Comparison

```elixir
{:ok, section} = Reports.baseline_comparison(experiment_id,
  dataset: "medqa",
  baselines: ["GPT-4", "GPT-3.5"]
)
```

## Published Baselines

The `Baselines` module includes published results from major evaluations:

```elixir
alias MedlumLlm.Telemetry.Baselines

# List all baselines for a dataset
baselines = Baselines.list_baselines("medqa")
# => [
#      %{model: "Med-PaLM 2", accuracy: 0.867, source: "Google 2023", year: 2023},
#      %{model: "GPT-4", accuracy: 0.861, source: "OpenAI 2023", year: 2023},
#      %{model: "Claude 3 Opus", accuracy: 0.863, source: "Anthropic 2024", year: 2024},
#      ...
#    ]

# Get specific baseline
{:ok, baseline} = Baselines.get_baseline("medqa", model: "GPT-4")

# Filter by year
{:ok, baseline} = Baselines.get_baseline("medqa", model: "Med-PaLM", year: 2023)

# Available datasets
Baselines.list_datasets()
# => ["medqa", "pubmedqa", "medmcqa"]
```

### Register Custom Baselines

Add your own baselines for comparison:

```elixir
:ok = Baselines.register_baseline(%{
  model: "BioMistral-7B (Q4_K_M)",
  dataset: "medqa",
  accuracy: 0.612,
  source: "Internal Evaluation 2026",
  year: 2026,
  notes: "Zero-shot, GGUF quantized"
})
```

## Integration with CrucibleBench

When `CrucibleBench` is available, the medical extensions integrate with:

- `CrucibleBench.wilson_score/3` - Confidence intervals for accuracy metrics
- `CrucibleBench.Environment.capture/0` - Environment fingerprinting

Without CrucibleBench, these features gracefully degrade:
- CI bounds become `nil`
- Environment is omitted from metadata

## Example: Complete Medical Evaluation

```elixir
alias MedlumLlm.Telemetry.{Experiment, Metrics, Reports, Baselines}

# 1. Start experiment
{:ok, exp} = Experiment.start_evaluation("medqa_biomistral_20260125",
  benchmark: :medqa_zero_shot,
  models: [:biomistral_7b],
  seed: 42,
  hypothesis: "BioMistral-7B achieves >70% on MedQA zero-shot",
  grant: %{program: "Clinical AI Benchmark", milestone: "Q2"}
)

# 2. Run evaluation (your code emits telemetry events)
MyEvaluator.run(exp.id, :medqa, :biomistral_7b)

# 3. Stop experiment
{:ok, _} = CrucibleTelemetry.stop_experiment(exp.id)

# 4. Calculate metrics
{:ok, model_metrics} = Metrics.calculate_model_metrics(exp.id)
{:ok, cvl_metrics} = Metrics.calculate_cvl_metrics(exp.id)

# 5. Generate evaluation report
{:ok, report} = Reports.generate(exp.id, :markdown,
  title: "Medical LLM Benchmark - Q2 Results",
  include_environment: true,
  include_baselines: true
)

# 6. Compare with baselines
baselines = Baselines.list_baselines("medqa")
gpt4 = Enum.find(baselines, & &1.model == "GPT-4")

delta = model_metrics[:biomistral_7b].accuracy - gpt4.accuracy
IO.puts("Accuracy delta vs GPT-4: #{Float.round(delta * 100, 1)}%")
# => "Accuracy delta vs GPT-4: -24.9%"

# 7. Export raw data
{:ok, _} = CrucibleTelemetry.export(exp.id, :csv, path: "results/medqa.csv")
{:ok, _} = CrucibleTelemetry.export(exp.id, :jsonl, path: "results/medqa.jsonl")

# 8. Write report
File.write!("reports/nsf_q2_report.md", report)
```
