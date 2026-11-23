defmodule MedlumLlm.Metrics.Alerts do
  @moduledoc """
  Predefined alert rules for medical AI systems.

  This module defines standard alert rules for monitoring medical AI
  evaluation and CVL performance. Alerts are configured using
  `MetricsEx.Alerting.define_rule/2`.

  ## Alert Categories

  ### Critical Alerts
  - `:low_accuracy` - Model accuracy dropped below 50%
  - `:cvl_critical_failure` - CVL recall dropped below 70%

  ### Warning Alerts
  - `:cvl_low_recall` - CVL recall below 80%
  - `:high_latency` - P95 latency exceeded 10 seconds
  - `:high_error_rate` - Error rate exceeded 10%
  - `:low_consensus` - Agent consensus rate below 60%

  ## Usage

      # Define all standard alerts at application startup
      MedlumLlm.Metrics.Alerts.define_standard_alerts()

      # Define only CVL alerts
      MedlumLlm.Metrics.Alerts.define_cvl_alerts()

      # Define only evaluation alerts
      MedlumLlm.Metrics.Alerts.define_eval_alerts()

      # Remove all medical alerts
      MedlumLlm.Metrics.Alerts.remove_all()
  """

  alias MetricsEx.Alerting

  @standard_alerts [
    # Critical alerts
    {:low_accuracy, %{
      metric: :medlum_eval_accuracy,
      condition: :less_than,
      threshold: 0.50,
      severity: :critical,
      message: "Model accuracy dropped below 50%"
    }},
    {:cvl_critical_failure, %{
      metric: :medlum_cvl_hallucination_recall,
      condition: :less_than,
      threshold: 0.70,
      severity: :critical,
      message: "CVL hallucination recall dropped below 70% (critical threshold)"
    }},

    # Warning alerts
    {:cvl_low_recall, %{
      metric: :medlum_cvl_hallucination_recall,
      condition: :less_than,
      threshold: 0.80,
      severity: :warning,
      message: "CVL hallucination recall dropped below 80%"
    }},
    {:high_latency, %{
      metric: :medlum_eval_inference_latency_ms,
      condition: :greater_than,
      threshold: 10_000,
      severity: :warning,
      message: "Inference latency exceeded 10 seconds (P95)"
    }},
    {:high_error_rate, %{
      metric: :medlum_eval_sample_failure_rate,
      condition: :greater_than,
      threshold: 0.10,
      severity: :warning,
      message: "Sample failure rate exceeded 10%"
    }},
    {:low_consensus, %{
      metric: :medlum_cvl_agreement_rate,
      condition: :less_than,
      threshold: 0.60,
      severity: :warning,
      message: "CVL agent consensus rate below 60%"
    }}
  ]

  @cvl_alerts [
    :cvl_critical_failure,
    :cvl_low_recall,
    :low_consensus
  ]

  @eval_alerts [
    :low_accuracy,
    :high_latency,
    :high_error_rate
  ]

  @doc """
  Define standard medical AI alert rules.

  Configures all predefined alert rules for medical evaluation
  and CVL monitoring. Call this once at application startup.

  ## Alerts Defined

  - `:low_accuracy` - Accuracy < 50% (critical)
  - `:cvl_critical_failure` - CVL recall < 70% (critical)
  - `:cvl_low_recall` - CVL recall < 80% (warning)
  - `:high_latency` - P95 latency > 10s (warning)
  - `:high_error_rate` - Error rate > 10% (warning)
  - `:low_consensus` - Consensus rate < 60% (warning)

  ## Examples

      iex> MedlumLlm.Metrics.Alerts.define_standard_alerts()
      :ok
  """
  @spec define_standard_alerts() :: :ok
  def define_standard_alerts do
    Enum.each(@standard_alerts, fn {name, config} ->
      Alerting.define_rule(name, config)
    end)

    :ok
  end

  @doc """
  Define only CVL-related alert rules.

  ## Examples

      iex> MedlumLlm.Metrics.Alerts.define_cvl_alerts()
      :ok
  """
  @spec define_cvl_alerts() :: :ok
  def define_cvl_alerts do
    @standard_alerts
    |> Enum.filter(fn {name, _config} -> name in @cvl_alerts end)
    |> Enum.each(fn {name, config} ->
      Alerting.define_rule(name, config)
    end)

    :ok
  end

  @doc """
  Define only evaluation-related alert rules.

  ## Examples

      iex> MedlumLlm.Metrics.Alerts.define_eval_alerts()
      :ok
  """
  @spec define_eval_alerts() :: :ok
  def define_eval_alerts do
    @standard_alerts
    |> Enum.filter(fn {name, _config} -> name in @eval_alerts end)
    |> Enum.each(fn {name, config} ->
      Alerting.define_rule(name, config)
    end)

    :ok
  end

  @doc """
  Define a custom alert rule.

  Convenience function for defining custom medical alerts with
  common defaults.

  ## Parameters

    - `name` - Alert rule name (atom)
    - `opts` - Alert options:
      - `:metric` - Metric name to monitor (required)
      - `:condition` - Comparison condition (required)
      - `:threshold` - Threshold value (required)
      - `:severity` - Alert severity (default: `:warning`)
      - `:message` - Alert message (default: auto-generated)

  ## Examples

      iex> MedlumLlm.Metrics.Alerts.define_alert(:custom_accuracy,
      ...>   metric: :medlum_eval_accuracy,
      ...>   condition: :less_than,
      ...>   threshold: 0.60,
      ...>   severity: :warning,
      ...>   message: "Custom accuracy threshold breached"
      ...> )
      :ok
  """
  @spec define_alert(atom(), keyword()) :: :ok
  def define_alert(name, opts) when is_atom(name) do
    metric = Keyword.fetch!(opts, :metric)
    condition = Keyword.fetch!(opts, :condition)
    threshold = Keyword.fetch!(opts, :threshold)
    severity = Keyword.get(opts, :severity, :warning)
    message = Keyword.get(opts, :message, "Alert: #{name}")

    Alerting.define_rule(name, %{
      metric: metric,
      condition: condition,
      threshold: threshold,
      severity: severity,
      message: message
    })

    :ok
  end

  @doc """
  Remove all medical alert rules.

  ## Examples

      iex> MedlumLlm.Metrics.Alerts.remove_all()
      :ok
  """
  @spec remove_all() :: :ok
  def remove_all do
    Enum.each(@standard_alerts, fn {name, _config} ->
      Alerting.remove_rule(name)
    end)

    :ok
  end

  @doc """
  Remove a specific alert rule.

  ## Examples

      iex> MedlumLlm.Metrics.Alerts.remove(:low_accuracy)
      :ok
  """
  @spec remove(atom()) :: :ok
  def remove(name) when is_atom(name) do
    Alerting.remove_rule(name)
  end

  @doc """
  Returns the list of all standard alert names.
  """
  @spec alert_names() :: list(atom())
  def alert_names do
    Enum.map(@standard_alerts, fn {name, _} -> name end)
  end

  @doc """
  Returns the configuration for a specific alert.

  ## Examples

      iex> MedlumLlm.Metrics.Alerts.get_config(:low_accuracy)
      %{metric: :medlum_eval_accuracy, condition: :less_than, threshold: 0.50, ...}
  """
  @spec get_config(atom()) :: map() | nil
  def get_config(name) do
    case Enum.find(@standard_alerts, fn {n, _} -> n == name end) do
      {_name, config} -> config
      nil -> nil
    end
  end
end
