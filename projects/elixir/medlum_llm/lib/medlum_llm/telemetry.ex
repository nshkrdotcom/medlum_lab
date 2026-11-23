defmodule MedlumLlm.Telemetry do
  @moduledoc """
  Medical AI telemetry extensions for MedlumLlm.

  This namespace provides medical-specific telemetry functionality for
  MedlumLlm and related medical NLP applications. It provides:

  - **Medical Events**: Telemetry event definitions for evaluation, CVL, and document processing
  - **Medical Metrics**: CVL accuracy, hallucination detection, and model metrics with CI
  - **Experiment Helpers**: Standardized metadata for medical evaluation experiments
  - **Grant Reports**: Markdown, LaTeX, and HTML report generation
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

  ## Quick Start

  ```elixir
  alias MedlumLlm.Telemetry.{Events, Metrics, Experiment, Reports, Baselines}

  # Start a medical evaluation experiment
  {:ok, exp} = Experiment.start_evaluation("medqa_biomistral_20260125",
    benchmark: :medqa_zero_shot,
    models: [:biomistral_7b],
    seed: 42
  )

  # Your evaluation code emits events...
  :telemetry.execute([:medlum_llm, :eval, :sample, :stop], measurements, metadata)

  # Calculate medical-specific metrics
  {:ok, model_metrics} = Metrics.calculate_model_metrics(exp.id)
  {:ok, cvl_metrics} = Metrics.calculate_cvl_metrics(exp.id)

  # Generate evaluation report
  {:ok, report} = Reports.generate(exp.id, :markdown,
    title: "Medical LLM Benchmark - Q2 Results",
    include_baselines: true
  )

  # Compare against published baselines
  baselines = Baselines.list_baselines("medqa")
  ```

  ## Event Schema

  Medical events follow the telemetry convention: `[:medlum_llm, domain, action, phase]`

  ### Evaluation Events

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
    predicted: String.t(),
    correct_answer: String.t(),
    correct: boolean()
  }
  ```

  ### CVL Verification Events

  ```elixir
  [:medlum_llm, :cvl, :verification, :stop]
  measurements: %{
    duration: integer(),
    agent_calls: integer()
  }
  metadata: %{
    verdict: :entailment | :contradiction | :neutral,
    confidence: float(),
    hallucination_detected: boolean(),
    agents: %{medication: %{...}, lab: %{...}, ...},
    disagreement_count: integer()
  }
  ```

  ## Modules

  - `MedlumLlm.Telemetry.Events` - 16 medical telemetry event definitions
  - `MedlumLlm.Telemetry.Metrics` - CVL and model metrics calculation
  - `MedlumLlm.Telemetry.Experiment` - Medical experiment helpers
  - `MedlumLlm.Telemetry.Reports` - Grant-ready report generation
  - `MedlumLlm.Telemetry.Baselines` - Published baseline data

  ## Integration with CrucibleBench

  When `CrucibleBench` is available (prompt 070), this module integrates with:
  - `CrucibleBench.wilson_score/3` for confidence intervals
  - `CrucibleBench.Environment.capture/0` for environment fingerprinting

  Without CrucibleBench, these features gracefully degrade (CI bounds become nil).
  """

  # Re-export key functions for convenience
  defdelegate medical_events, to: MedlumLlm.Telemetry.Events
  defdelegate evaluation_events, to: MedlumLlm.Telemetry.Events
  defdelegate cvl_events, to: MedlumLlm.Telemetry.Events
  defdelegate document_events, to: MedlumLlm.Telemetry.Events

  defdelegate calculate_cvl_metrics(experiment_id), to: MedlumLlm.Telemetry.Metrics
  defdelegate calculate_model_metrics(experiment_id), to: MedlumLlm.Telemetry.Metrics
  defdelegate calculate_model_metrics(experiment_id, opts), to: MedlumLlm.Telemetry.Metrics

  defdelegate start_evaluation(name, opts), to: MedlumLlm.Telemetry.Experiment

  defdelegate generate_report(experiment_id, format),
    to: MedlumLlm.Telemetry.Reports,
    as: :generate

  defdelegate generate_report(experiment_id, format, opts),
    to: MedlumLlm.Telemetry.Reports,
    as: :generate

  defdelegate list_baselines(dataset), to: MedlumLlm.Telemetry.Baselines
  defdelegate get_baseline(dataset, opts), to: MedlumLlm.Telemetry.Baselines
end
