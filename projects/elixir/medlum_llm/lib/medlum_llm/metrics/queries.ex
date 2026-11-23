defmodule MedlumLlm.Metrics.Queries do
  @moduledoc """
  Query helpers for medical metrics dashboards.

  This module provides pre-built query functions for common medical AI
  dashboard views. These functions build on `MetricsEx.rollup/2` and
  `MetricsEx.query/2` to provide dashboard-ready aggregations.

  ## Dashboard Categories

  ### CVL Performance Dashboard
  - `verdict_distribution/1` - Verdict counts by type
  - `agent_performance/1` - Per-agent duration stats
  - `hallucination_detection_metrics/1` - Precision/recall/F1

  ### Model Comparison Dashboard
  - `accuracy_by_model/1` - Accuracy grouped by model and dataset
  - `latency_by_model/1` - Latency percentiles by model

  ### Error Analysis Dashboard
  - `errors_by_type/1` - Error counts by type and model

  ## Usage

      # Get verdict distribution for last 24 hours
      MedlumLlm.Metrics.Queries.verdict_distribution(window: :last_24h)

      # Get agent performance with custom window
      MedlumLlm.Metrics.Queries.agent_performance(window: :last_7d)

      # Calculate hallucination detection metrics
      MedlumLlm.Metrics.Queries.hallucination_detection_metrics(
        window: :last_24h,
        verifier_type: :ensemble
      )
  """

  alias MetricsEx

  @doc """
  Get CVL verdict distribution.

  Returns counts of each verdict type, optionally grouped by verifier type.

  ## Options

    - `:window` - Time window (`:last_hour`, `:last_24h`, `:last_7d`), default: `:last_24h`
    - `:verifier_type` - Filter by verifier type (`:ensemble`, `:single_agent`)

  ## Returns

  Map of verdict to count:

      %{
        "entailment/ensemble" => %{sum: 150},
        "contradiction/ensemble" => %{sum: 45},
        "neutral/ensemble" => %{sum: 30}
      }

  ## Examples

      iex> MedlumLlm.Metrics.Queries.verdict_distribution()
      %{"entailment/ensemble" => %{sum: 150}, ...}

      iex> MedlumLlm.Metrics.Queries.verdict_distribution(window: :last_7d)
      %{"entailment/ensemble" => %{sum: 1050}, ...}
  """
  @spec verdict_distribution(keyword()) :: map()
  def verdict_distribution(opts \\ []) do
    window = Keyword.get(opts, :window, :last_24h)
    verifier_type = Keyword.get(opts, :verifier_type)

    query_opts = [
      group_by: [:verdict, :verifier_type],
      aggregations: [:sum],
      window: window
    ]

    query_opts =
      if verifier_type do
        Keyword.put(query_opts, :tags, %{verifier_type: verifier_type})
      else
        query_opts
      end

    MetricsEx.rollup(:medlum_cvl_verdict_count, query_opts)
  end

  @doc """
  Get per-agent performance summary.

  Returns timing statistics for each CVL agent, useful for identifying
  slow agents or performance bottlenecks.

  ## Options

    - `:window` - Time window (default: `:last_24h`)

  ## Returns

  Map of agent to performance stats:

      %{
        "medication" => %{mean: 45.2, p50: 42.0, p95: 85.0, count: 1000},
        "lab" => %{mean: 52.1, p50: 48.0, p95: 92.0, count: 1000},
        ...
      }

  ## Examples

      iex> MedlumLlm.Metrics.Queries.agent_performance()
      %{"medication" => %{mean: 45.2, count: 1000}, ...}
  """
  @spec agent_performance(keyword()) :: map()
  def agent_performance(opts \\ []) do
    window = Keyword.get(opts, :window, :last_24h)

    MetricsEx.rollup(:medlum_cvl_agent_duration_ms,
      group_by: [:agent],
      aggregations: [:mean, :p50, :p95, :count],
      window: window
    )
  end

  @doc """
  Calculate hallucination detection precision, recall, and F1.

  Computes confusion matrix metrics from the recorded detection outcomes.
  This is a key metric for evaluating CVL effectiveness.

  ## Options

    - `:window` - Time window (default: `:last_24h`)
    - `:verifier_type` - Filter by verifier type

  ## Returns

      %{
        precision: 0.92,
        recall: 0.88,
        f1: 0.90,
        true_positives: 176,
        false_positives: 15,
        false_negatives: 24,
        true_negatives: 785,
        total: 1000
      }

  ## Examples

      iex> MedlumLlm.Metrics.Queries.hallucination_detection_metrics()
      %{precision: 0.92, recall: 0.88, f1: 0.90, ...}
  """
  @spec hallucination_detection_metrics(keyword()) :: map()
  def hallucination_detection_metrics(opts \\ []) do
    window = Keyword.get(opts, :window, :last_24h)
    verifier_type = Keyword.get(opts, :verifier_type)

    query_opts = [
      group_by: [:outcome],
      aggregations: [:sum],
      window: window
    ]

    query_opts =
      if verifier_type do
        Keyword.put(query_opts, :tags, %{verifier_type: verifier_type})
      else
        query_opts
      end

    outcomes = MetricsEx.rollup(:medlum_cvl_detection_outcome, query_opts)

    tp = get_outcome_sum(outcomes, "true_positive")
    fp = get_outcome_sum(outcomes, "false_positive")
    fn_ = get_outcome_sum(outcomes, "false_negative")
    tn = get_outcome_sum(outcomes, "true_negative")

    precision = safe_divide(tp, tp + fp)
    recall = safe_divide(tp, tp + fn_)
    f1 = safe_divide(2 * precision * recall, precision + recall)

    %{
      precision: precision,
      recall: recall,
      f1: f1,
      true_positives: tp,
      false_positives: fp,
      false_negatives: fn_,
      true_negatives: tn,
      total: tp + fp + fn_ + tn
    }
  end

  @doc """
  Get accuracy grouped by model and dataset.

  Returns accuracy statistics for each model/dataset combination,
  useful for model comparison dashboards.

  ## Options

    - `:window` - Time window (default: `:last_7d`)

  ## Returns

      %{
        "biomistral_7b/medqa" => %{mean: 0.75, min: 0.72, max: 0.78, count: 10},
        "openbiollm_8b/medqa" => %{mean: 0.68, min: 0.65, max: 0.71, count: 10},
        ...
      }

  ## Examples

      iex> MedlumLlm.Metrics.Queries.accuracy_by_model()
      %{"biomistral_7b/medqa" => %{mean: 0.75, ...}, ...}
  """
  @spec accuracy_by_model(keyword()) :: map()
  def accuracy_by_model(opts \\ []) do
    window = Keyword.get(opts, :window, :last_7d)

    MetricsEx.rollup(:medlum_eval_accuracy,
      group_by: [:model, :dataset],
      aggregations: [:mean, :min, :max, :count],
      window: window
    )
  end

  @doc """
  Get latency percentiles by model.

  Returns latency distribution statistics for each model and benchmark,
  useful for performance monitoring.

  ## Options

    - `:window` - Time window (default: `:last_24h`)

  ## Returns

      %{
        "biomistral_7b/zero_shot" => %{mean: 1523.5, p50: 1400.0, p95: 2800.0, p99: 3500.0, count: 1000},
        ...
      }

  ## Examples

      iex> MedlumLlm.Metrics.Queries.latency_by_model()
      %{"biomistral_7b/zero_shot" => %{mean: 1523.5, ...}, ...}
  """
  @spec latency_by_model(keyword()) :: map()
  def latency_by_model(opts \\ []) do
    window = Keyword.get(opts, :window, :last_24h)

    MetricsEx.rollup(:medlum_eval_inference_latency_ms,
      group_by: [:model, :benchmark],
      aggregations: [:mean, :p50, :p95, :p99, :count],
      window: window
    )
  end

  @doc """
  Get error distribution by type and model.

  Returns error counts grouped by error type and model,
  useful for debugging and reliability monitoring.

  ## Options

    - `:window` - Time window (default: `:last_24h`)

  ## Returns

      %{
        "timeout/biomistral_7b" => %{sum: 5},
        "provider_error/openbiollm_8b" => %{sum: 12},
        ...
      }

  ## Examples

      iex> MedlumLlm.Metrics.Queries.errors_by_type()
      %{"timeout/biomistral_7b" => %{sum: 5}, ...}
  """
  @spec errors_by_type(keyword()) :: map()
  def errors_by_type(opts \\ []) do
    window = Keyword.get(opts, :window, :last_24h)

    MetricsEx.rollup(:medlum_eval_error_count,
      group_by: [:error_type, :model],
      aggregations: [:sum],
      window: window
    )
  end

  @doc """
  Get consensus agreement rate distribution.

  Returns statistics on how often CVL agents reach consensus.

  ## Options

    - `:window` - Time window (default: `:last_24h`)

  ## Returns

      %{
        "" => %{mean: 0.85, p50: 1.0, min: 0.4, max: 1.0, count: 1000}
      }

  ## Examples

      iex> MedlumLlm.Metrics.Queries.consensus_distribution()
      %{"" => %{mean: 0.85, ...}}
  """
  @spec consensus_distribution(keyword()) :: map()
  def consensus_distribution(opts \\ []) do
    window = Keyword.get(opts, :window, :last_24h)

    MetricsEx.rollup(:medlum_cvl_agreement_rate,
      group_by: [],
      aggregations: [:mean, :p50, :min, :max, :count],
      window: window
    )
  end

  @doc """
  Get accuracy with confidence intervals.

  Fetches accuracy metrics along with Wilson CI bounds for
  statistical reporting.

  ## Options

    - `:window` - Time window (default: `:last_7d`)
    - `:model` - Filter by model name
    - `:dataset` - Filter by dataset name

  ## Returns

  List of accuracy entries with CI:

      [
        %{model: "biomistral_7b", dataset: "medqa", accuracy: 0.75, ci_lower: 0.68, ci_upper: 0.81},
        ...
      ]

  ## Examples

      iex> MedlumLlm.Metrics.Queries.accuracy_with_ci(model: "biomistral_7b")
      [%{model: "biomistral_7b", accuracy: 0.75, ci_lower: 0.68, ci_upper: 0.81}, ...]
  """
  @spec accuracy_with_ci(keyword()) :: list(map())
  def accuracy_with_ci(opts \\ []) do
    window = Keyword.get(opts, :window, :last_7d)
    model = Keyword.get(opts, :model)
    dataset = Keyword.get(opts, :dataset)

    tags_filter =
      %{}
      |> maybe_put(:model, model)
      |> maybe_put(:dataset, dataset)

    # Get accuracy values
    accuracy_metrics =
      MetricsEx.query(:medlum_eval_accuracy,
        group_by: [:model, :dataset],
        aggregation: :mean,
        window: window,
        tags: tags_filter
      )

    # Get CI lower bounds
    ci_lower_metrics =
      MetricsEx.query(:medlum_eval_accuracy_ci_lower,
        group_by: [:model, :dataset],
        aggregation: :mean,
        window: window,
        tags: tags_filter
      )

    # Get CI upper bounds
    ci_upper_metrics =
      MetricsEx.query(:medlum_eval_accuracy_ci_upper,
        group_by: [:model, :dataset],
        aggregation: :mean,
        window: window,
        tags: tags_filter
      )

    # Merge results
    merge_accuracy_with_ci(accuracy_metrics, ci_lower_metrics, ci_upper_metrics)
  end

  # Private functions

  defp get_outcome_sum(outcomes, outcome_key) do
    case Map.get(outcomes, outcome_key) do
      %{sum: sum} -> sum
      nil -> 0
    end
  end

  defp safe_divide(numerator, denominator) when is_number(denominator) do
    if denominator == 0 do
      0.0
    else
      numerator / denominator
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp merge_accuracy_with_ci(accuracy_metrics, ci_lower_metrics, ci_upper_metrics) do
    # Convert lists to maps keyed by {model, dataset}
    accuracy_map = build_metric_map(accuracy_metrics, :mean)
    ci_lower_map = build_metric_map(ci_lower_metrics, :mean)
    ci_upper_map = build_metric_map(ci_upper_metrics, :mean)

    # Merge into list of results
    accuracy_map
    |> Enum.map(fn {{model, dataset}, accuracy} ->
      %{
        model: model,
        dataset: dataset,
        accuracy: accuracy,
        ci_lower: Map.get(ci_lower_map, {model, dataset}),
        ci_upper: Map.get(ci_upper_map, {model, dataset})
      }
    end)
  end

  defp build_metric_map(metrics, agg_key) when is_list(metrics) do
    Enum.into(metrics, %{}, fn result ->
      key = {result[:model], result[:dataset]}
      value = Map.get(result, agg_key)
      {key, value}
    end)
  end

  defp build_metric_map(_metrics, _agg_key), do: %{}
end
