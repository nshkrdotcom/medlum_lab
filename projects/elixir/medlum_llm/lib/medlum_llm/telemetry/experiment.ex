defmodule MedlumLlm.Telemetry.Experiment do
  @moduledoc """
  Medical-specific experiment metadata and helpers.

  This module provides convenience functions for starting medical evaluation
  experiments with standardized metadata. It wraps `CrucibleTelemetry.start_experiment/1`
  with medical-specific defaults and helpers.

  ## Features

  - Standardized metadata schema for medical evaluations
  - Optional environment fingerprint attachment (via CrucibleBench)
  - Pre-configured for grant reporting requirements

  ## Usage

  ```elixir
  alias MedlumLlm.Telemetry.Experiment

  # Start a medical evaluation experiment
  {:ok, exp} = Experiment.start_evaluation("medqa_biomistral_20260125",
    benchmark: :medqa_zero_shot,
    models: [:biomistral_7b],
    seed: 42,
    hypothesis: "BioMistral-7B achieves >70% on MedQA zero-shot"
  )

  # Environment is captured if CrucibleBench is available
  exp.metadata.environment
  # => %{elixir_version: "1.17.0", otp_version: "27.0", ...}
  ```

  ## Environment Fingerprinting

  Environment capture is handled by `CrucibleBench.Environment.capture/0` (prompt 070).
  This module stores whatever environment fingerprint the application provides in
  experiment metadata. When CrucibleBench is not available, the environment field
  is omitted or set to `nil`.
  """

  alias CrucibleTelemetry.Experiment

  @typedoc "Medical evaluation options"
  @type eval_opts :: [
          benchmark: atom() | String.t(),
          models: [atom()],
          seed: non_neg_integer(),
          hypothesis: String.t(),
          concurrency: pos_integer(),
          dataset: map(),
          grant: map(),
          environment: map() | nil,
          tags: [String.t()],
          condition: String.t(),
          sample_size: non_neg_integer(),
          retention: atom()
        ]

  @doc """
  Start experiment with medical evaluation metadata.

  Wraps `CrucibleTelemetry.start_experiment/1` with medical-specific defaults
  and standardized metadata schema.

  ## Parameters

  - `name` - Experiment name (required)
  - `opts` - Evaluation options:
    - `:benchmark` - Benchmark identifier (e.g., `:medqa_zero_shot`)
    - `:models` - List of model atoms being evaluated
    - `:seed` - Random seed for reproducibility (default: 42)
    - `:hypothesis` - What you're testing
    - `:concurrency` - Number of concurrent evaluations (default: 1)
    - `:dataset` - Dataset configuration map
    - `:grant` - Grant context (program, milestone, etc.)
    - `:environment` - Pre-captured environment fingerprint (or auto-captured)
    - `:tags` - Additional tags for categorization
    - `:condition` - Experimental condition (default: "evaluation")
    - `:sample_size` - Target sample size
    - `:retention` - Retention policy (`:full`, `:errors_only`, `:summary_only`)

  ## Returns

  - `{:ok, Experiment.t()}` - Started experiment
  - `{:error, term()}` - Error from experiment start

  ## Examples

      {:ok, exp} = Experiment.start_evaluation("medqa_gpt4_baseline",
        benchmark: :medqa_zero_shot,
        models: [:gpt_4],
        seed: 42,
        hypothesis: "GPT-4 matches published 86.1% on MedQA",
        grant: %{program: "Clinical AI Benchmark", milestone: "Q2"}
      )
  """
  @spec start_evaluation(String.t(), eval_opts()) ::
          {:ok, Experiment.t()} | {:error, term()}
  def start_evaluation(name, opts \\ []) do
    # Build standardized metadata
    metadata = evaluation_metadata(opts)

    # Auto-capture environment if not provided and CrucibleBench is available
    metadata = maybe_capture_environment(metadata, opts)

    # Build tags from options
    tags = build_tags(opts)

    # Start experiment with medical defaults
    Experiment.start(
      name: name,
      hypothesis: Keyword.get(opts, :hypothesis),
      condition: Keyword.get(opts, :condition, "evaluation"),
      tags: tags,
      metadata: metadata,
      sample_size: Keyword.get(opts, :sample_size)
    )
  end

  @doc """
  Add environment fingerprint to an existing experiment.

  Updates the experiment metadata with an environment fingerprint captured
  via `CrucibleBench.Environment.capture/0`. If CrucibleBench is not available,
  returns the experiment unchanged with environment set to `nil`.

  ## Parameters

  - `experiment` - The experiment struct to update

  ## Returns

  Updated experiment struct with environment in metadata.

  ## Examples

      {:ok, exp} = CrucibleTelemetry.start_experiment(name: "test")
      exp = Experiment.with_environment(exp)
      exp.metadata.environment
      # => %{elixir_version: "1.17.0", ...} (if CrucibleBench available)
  """
  @spec with_environment(Experiment.t()) :: Experiment.t()
  def with_environment(experiment) do
    env = capture_environment()
    updated_metadata = Map.put(experiment.metadata, :environment, env)
    %{experiment | metadata: updated_metadata}
  end

  @doc """
  Build standard metadata for medical evaluations.

  Creates a standardized metadata map for medical AI evaluation experiments.

  ## Options

  - `:benchmark` - Benchmark identifier
  - `:models` - List of model atoms
  - `:seed` - Random seed (default: 42)
  - `:concurrency` - Concurrent evaluations (default: 1)
  - `:dataset` - Dataset configuration
  - `:grant` - Grant context
  - `:retention` - Retention policy
  - `:environment` - Pre-captured environment (or nil)

  ## Examples

      metadata = Experiment.evaluation_metadata(
        benchmark: :medqa_zero_shot,
        models: [:biomistral_7b],
        seed: 42
      )
      # => %{benchmark: :medqa_zero_shot, models: [:biomistral_7b], seed: 42, ...}
  """
  @spec evaluation_metadata(keyword()) :: map()
  def evaluation_metadata(opts) do
    %{
      # Run configuration
      benchmark: Keyword.get(opts, :benchmark),
      models: Keyword.get(opts, :models, []),
      seed: Keyword.get(opts, :seed, 42),
      concurrency: Keyword.get(opts, :concurrency, 1),
      retention: Keyword.get(opts, :retention, :full),

      # Dataset information (if provided)
      dataset: Keyword.get(opts, :dataset),

      # Grant context (if provided)
      grant: Keyword.get(opts, :grant),

      # Environment placeholder (filled by with_environment or auto-capture)
      environment: Keyword.get(opts, :environment)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  # Private helpers

  defp build_tags(opts) do
    base_tags = Keyword.get(opts, :tags, [])

    # Auto-add benchmark as tag if present
    benchmark_tag =
      case Keyword.get(opts, :benchmark) do
        nil -> []
        benchmark -> [to_string(benchmark)]
      end

    # Auto-add model names as tags
    model_tags =
      opts
      |> Keyword.get(:models, [])
      |> Enum.map(&to_string/1)

    Enum.uniq(["evaluation" | base_tags] ++ benchmark_tag ++ model_tags)
  end

  defp maybe_capture_environment(metadata, opts) do
    # If environment already provided, use it
    if Keyword.has_key?(opts, :environment) do
      metadata
    else
      # Try to auto-capture
      env = capture_environment()
      if env, do: Map.put(metadata, :environment, env), else: metadata
    end
  end

  defp capture_environment do
    # Try to use CrucibleBench.Environment.capture/0 if available
    if Code.ensure_loaded?(CrucibleBench.Environment) and
         function_exported?(CrucibleBench.Environment, :capture, 0) do
      apply(CrucibleBench.Environment, :capture, [])
    else
      nil
    end
  end
end
