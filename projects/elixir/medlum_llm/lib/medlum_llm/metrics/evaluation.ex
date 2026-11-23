defmodule MedlumLlm.Metrics.Evaluation do
  @moduledoc """
  Evaluation harness metrics for medical AI benchmarks.

  This module provides metrics recording for medical AI evaluation runs,
  including accuracy tracking with confidence intervals, latency measurements,
  and error categorization.

  ## Metrics

  - `medlum_eval_accuracy` - Gauge for model accuracy (0.0-1.0)
  - `medlum_eval_accuracy_ci_lower` - Gauge for Wilson CI lower bound
  - `medlum_eval_accuracy_ci_upper` - Gauge for Wilson CI upper bound
  - `medlum_eval_inference_latency_ms` - Histogram of inference latency
  - `medlum_eval_error_count` - Counter by error type

  ## Error Types

  Common error categories tracked:

  - `:timeout` - Inference exceeded timeout
  - `:provider_error` - Ollama/HuggingFace error
  - `:parse_error` - Could not extract answer from response
  - `:validation_error` - Response failed validation
  - `:network_error` - Connection failures
  - `:oom_error` - Out of memory

  ## Usage

      # Record accuracy
      MedlumLlm.Metrics.Evaluation.record_accuracy(0.75,
        model: "biomistral_7b",
        dataset: "medqa",
        benchmark: "zero_shot"
      )

      # Record accuracy with Wilson confidence interval
      MedlumLlm.Metrics.Evaluation.record_accuracy_with_ci(0.75, 0.68, 0.81,
        model: "biomistral_7b",
        dataset: "medqa",
        benchmark: "zero_shot"
      )

      # Record latency
      MedlumLlm.Metrics.Evaluation.record_latency(1523.5,
        model: "biomistral_7b",
        benchmark: "zero_shot"
      )

      # Record error
      MedlumLlm.Metrics.Evaluation.record_error(:timeout,
        model: "biomistral_7b",
        benchmark: "zero_shot"
      )
  """

  alias MetricsEx

  @error_types [
    :timeout,
    :provider_error,
    :parse_error,
    :validation_error,
    :network_error,
    :oom_error,
    :unknown
  ]

  @doc """
  Returns the list of recognized error types.
  """
  @spec error_types() :: list(atom())
  def error_types, do: @error_types

  @doc """
  Record model accuracy for a benchmark.

  ## Parameters

    - `accuracy` - Accuracy value (0.0-1.0)
    - `opts` - Options (required):
      - `:model` - Model name (required)
      - `:dataset` - Dataset name (required)
      - `:benchmark` - Benchmark name (default: "default")
      - `:run_id` - Run identifier

  ## Examples

      iex> MedlumLlm.Metrics.Evaluation.record_accuracy(0.75,
      ...>   model: "biomistral_7b",
      ...>   dataset: "medqa",
      ...>   benchmark: "zero_shot"
      ...> )
      :ok
  """
  @spec record_accuracy(float(), keyword()) :: :ok
  def record_accuracy(accuracy, opts) when is_number(accuracy) do
    model = Keyword.fetch!(opts, :model)
    dataset = Keyword.fetch!(opts, :dataset)
    benchmark = Keyword.get(opts, :benchmark, "default")
    run_id = Keyword.get(opts, :run_id)

    tags = %{
      model: normalize_tag(model),
      dataset: normalize_tag(dataset),
      benchmark: normalize_tag(benchmark)
    }

    tags = if run_id, do: Map.put(tags, :run_id, run_id), else: tags

    MetricsEx.gauge(:medlum_eval_accuracy, accuracy, tags: tags)
  end

  @doc """
  Record accuracy with Wilson confidence interval.

  Records the accuracy along with the lower and upper bounds of the
  Wilson score confidence interval. The CI values should be computed
  using `CrucibleBench.wilson_score/3` or equivalent.

  ## Parameters

    - `accuracy` - Accuracy value (0.0-1.0)
    - `ci_lower` - Wilson CI lower bound
    - `ci_upper` - Wilson CI upper bound
    - `opts` - Options (required):
      - `:model` - Model name (required)
      - `:dataset` - Dataset name (required)
      - `:benchmark` - Benchmark name (default: "default")
      - `:run_id` - Run identifier

  ## Examples

      iex> MedlumLlm.Metrics.Evaluation.record_accuracy_with_ci(0.75, 0.68, 0.81,
      ...>   model: "biomistral_7b",
      ...>   dataset: "medqa"
      ...> )
      :ok
  """
  @spec record_accuracy_with_ci(float(), float(), float(), keyword()) :: :ok
  def record_accuracy_with_ci(accuracy, ci_lower, ci_upper, opts)
      when is_number(accuracy) and is_number(ci_lower) and is_number(ci_upper) do
    # Record the main accuracy
    record_accuracy(accuracy, opts)

    model = Keyword.fetch!(opts, :model)
    dataset = Keyword.fetch!(opts, :dataset)
    benchmark = Keyword.get(opts, :benchmark, "default")

    tags = %{
      model: normalize_tag(model),
      dataset: normalize_tag(dataset),
      benchmark: normalize_tag(benchmark)
    }

    # Record CI bounds as separate gauges
    MetricsEx.gauge(:medlum_eval_accuracy_ci_lower, ci_lower, tags: tags)
    MetricsEx.gauge(:medlum_eval_accuracy_ci_upper, ci_upper, tags: tags)
  end

  @doc """
  Record inference latency.

  ## Parameters

    - `latency_ms` - Latency in milliseconds
    - `opts` - Options (required):
      - `:model` - Model name (required)
      - `:benchmark` - Benchmark name (default: "default")
      - `:provider` - Provider name (e.g., :ollama, :huggingface)
      - `:run_id` - Run identifier

  ## Examples

      iex> MedlumLlm.Metrics.Evaluation.record_latency(1523.5,
      ...>   model: "biomistral_7b",
      ...>   benchmark: "zero_shot"
      ...> )
      :ok
  """
  @spec record_latency(number(), keyword()) :: :ok
  def record_latency(latency_ms, opts) when is_number(latency_ms) do
    model = Keyword.fetch!(opts, :model)
    benchmark = Keyword.get(opts, :benchmark, "default")
    provider = Keyword.get(opts, :provider)

    tags = %{
      model: normalize_tag(model),
      benchmark: normalize_tag(benchmark)
    }

    tags = if provider, do: Map.put(tags, :provider, provider), else: tags

    MetricsEx.histogram(:medlum_eval_inference_latency_ms, latency_ms, tags: tags)
  end

  @doc """
  Record error by category.

  ## Parameters

    - `error_type` - Error category atom
    - `opts` - Options:
      - `:model` - Model name (default: "unknown")
      - `:benchmark` - Benchmark name (default: "default")
      - `:run_id` - Run identifier

  ## Examples

      iex> MedlumLlm.Metrics.Evaluation.record_error(:timeout,
      ...>   model: "biomistral_7b",
      ...>   benchmark: "zero_shot"
      ...> )
      :ok

      iex> MedlumLlm.Metrics.Evaluation.record_error(:provider_error,
      ...>   model: "openbiollm_8b"
      ...> )
      :ok
  """
  @spec record_error(atom(), keyword()) :: :ok
  def record_error(error_type, opts \\ []) when is_atom(error_type) do
    model = Keyword.get(opts, :model, "unknown")
    benchmark = Keyword.get(opts, :benchmark, "default")

    MetricsEx.increment(:medlum_eval_error_count, 1,
      tags: %{
        error_type: error_type,
        model: normalize_tag(model),
        benchmark: normalize_tag(benchmark)
      }
    )
  end

  @doc """
  Record sample completion.

  Convenience function for recording a successful sample evaluation
  with associated metrics.

  ## Parameters

    - `result` - Map with sample result data:
      - `:latency_ms` - Sample latency (required)
      - `:model` - Model name (required)
      - `:benchmark` - Benchmark name
      - `:output_tokens` - Number of output tokens
      - `:run_id` - Run identifier

  ## Examples

      iex> MedlumLlm.Metrics.Evaluation.record_sample_complete(%{
      ...>   latency_ms: 1523.5,
      ...>   model: "biomistral_7b",
      ...>   benchmark: "zero_shot",
      ...>   output_tokens: 42
      ...> })
      :ok
  """
  @spec record_sample_complete(map()) :: :ok
  def record_sample_complete(result) when is_map(result) do
    latency_ms = Map.fetch!(result, :latency_ms)
    model = Map.fetch!(result, :model)
    benchmark = Map.get(result, :benchmark, "default")

    record_latency(latency_ms, model: model, benchmark: benchmark)
  end

  @doc """
  Record sample failure with error classification.

  ## Parameters

    - `context` - Map with sample context:
      - `:model` - Model name
      - `:benchmark` - Benchmark name
      - `:run_id` - Run identifier
    - `reason` - Error reason (will be classified)

  ## Examples

      iex> MedlumLlm.Metrics.Evaluation.record_sample_failed(
      ...>   %{model: "biomistral_7b", benchmark: "zero_shot"},
      ...>   {:timeout, 30000}
      ...> )
      :ok
  """
  @spec record_sample_failed(map(), term()) :: :ok
  def record_sample_failed(context, reason) do
    error_type = classify_error(reason)
    model = Map.get(context, :model, "unknown")
    benchmark = Map.get(context, :benchmark, "default")

    record_error(error_type, model: model, benchmark: benchmark)
  end

  # Private functions

  defp normalize_tag(value) when is_atom(value), do: value
  defp normalize_tag(value) when is_binary(value), do: value
  defp normalize_tag(value), do: to_string(value)

  @doc false
  def classify_error(reason) do
    cond do
      timeout_error?(reason) -> :timeout
      network_error?(reason) -> :network_error
      provider_error?(reason) -> :provider_error
      parse_error?(reason) -> :parse_error
      validation_error?(reason) -> :validation_error
      oom_error?(reason) -> :oom_error
      true -> :unknown
    end
  end

  defp timeout_error?({:timeout, _}), do: true
  defp timeout_error?({:error, :timeout}), do: true
  defp timeout_error?(:timeout), do: true
  defp timeout_error?(_), do: false

  defp network_error?({:error, :econnrefused}), do: true
  defp network_error?({:error, :nxdomain}), do: true
  defp network_error?({:error, :ehostunreach}), do: true
  defp network_error?(_), do: false

  defp provider_error?({:error, {:http_error, _}}), do: true
  defp provider_error?(%{status: status}) when status >= 500, do: true
  defp provider_error?(_), do: false

  defp parse_error?({:error, :parse_error}), do: true
  defp parse_error?(_), do: false

  defp validation_error?({:error, :validation_error}), do: true
  defp validation_error?(_), do: false

  defp oom_error?({:error, :oom}), do: true
  defp oom_error?(%ErlangError{original: :system_limit}), do: true
  defp oom_error?(_), do: false
end
