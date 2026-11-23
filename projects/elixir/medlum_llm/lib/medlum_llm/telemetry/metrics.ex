defmodule MedlumLlm.Telemetry.Metrics do
  @moduledoc """
  Medical-specific metrics calculation from telemetry events.

  This module provides specialized metrics for medical AI evaluation:

  - **CVL Metrics**: Hallucination detection accuracy, precision, recall, F1, agent agreement
  - **Model Metrics**: Per-model accuracy with confidence intervals, latency percentiles

  ## Usage

  ```elixir
  # Calculate CVL metrics
  {:ok, cvl} = MedlumLlm.Telemetry.Metrics.calculate_cvl_metrics(experiment_id)
  cvl.cvl_accuracy         # => 0.87
  cvl.hallucination_f1     # => 0.925

  # Calculate per-model metrics
  {:ok, models} = MedlumLlm.Telemetry.Metrics.calculate_model_metrics(experiment_id)
  models[:biomistral_7b].accuracy  # => 0.612
  ```

  ## Wilson Score CI

  When `CrucibleBench` is available (prompt 070), model metrics include Wilson score
  confidence intervals. Otherwise, CI bounds are `nil`.
  """

  alias CrucibleTelemetry.Store

  @typedoc "CVL verification metrics"
  @type cvl_metrics :: %{
          cvl_accuracy: float(),
          hallucination_precision: float(),
          hallucination_recall: float(),
          hallucination_f1: float(),
          agent_agreement_rate: float(),
          mean_verification_latency_ms: float(),
          total_verifications: non_neg_integer(),
          entailment_count: non_neg_integer(),
          contradiction_count: non_neg_integer(),
          neutral_count: non_neg_integer()
        }

  @typedoc "Per-model evaluation metrics"
  @type model_metrics :: %{
          model: atom(),
          accuracy: float(),
          accuracy_ci_lower: float() | nil,
          accuracy_ci_upper: float() | nil,
          total_samples: non_neg_integer(),
          correct: non_neg_integer(),
          errors: non_neg_integer(),
          latency_p50: float() | nil,
          latency_p95: float() | nil,
          tokens_per_second: float() | nil
        }

  @doc """
  Calculate CVL metrics from experiment events.

  Analyzes CVL verification events to compute:
  - Overall CVL accuracy
  - Hallucination detection precision, recall, and F1
  - Agent agreement rate
  - Mean verification latency

  ## Parameters

  - `experiment_id` - The experiment ID to analyze

  ## Returns

  - `{:ok, cvl_metrics()}` - Calculated metrics
  - `{:error, :no_data}` - No CVL verification events found

  ## Event Requirements

  Expects events of type `[:medlum_llm, :cvl, :verification, :stop]` with metadata:

  ```elixir
  %{
    verdict: :entailment | :contradiction | :neutral,
    hallucination_detected: boolean(),
    agents: %{...},
    disagreement_count: integer()
  }
  ```

  ## Examples

      {:ok, metrics} = MedlumLlm.Telemetry.Metrics.calculate_cvl_metrics("exp_123")
      metrics.cvl_accuracy
      # => 0.87
  """
  @spec calculate_cvl_metrics(String.t()) :: {:ok, cvl_metrics()} | {:error, :no_data}
  def calculate_cvl_metrics(experiment_id) do
    events = Store.get_all(experiment_id)

    cvl_events =
      Enum.filter(events, fn e ->
        e.event_name == [:medlum_llm, :cvl, :verification, :stop]
      end)

    if Enum.empty?(cvl_events) do
      {:error, :no_data}
    else
      {:ok, do_calculate_cvl_metrics(cvl_events)}
    end
  end

  @doc """
  Calculate per-model metrics from experiment events.

  Groups sample evaluation events by model and calculates:
  - Accuracy with optional Wilson score CI
  - Sample counts (total, correct, errors)
  - Latency percentiles (p50, p95)
  - Tokens per second throughput

  ## Parameters

  - `experiment_id` - The experiment ID to analyze
  - `opts` - Options:
    - `:confidence_level` - CI confidence level (default: 0.95)

  ## Returns

  - `{:ok, %{atom() => model_metrics()}}` - Metrics keyed by model atom
  - `{:error, :no_data}` - No sample evaluation events found

  ## Event Requirements

  Expects events of type `[:medlum_llm, :eval, :sample, :stop]` with metadata:

  ```elixir
  %{
    model: atom(),
    correct: boolean(),
    # ... other fields
  }
  ```

  ## Examples

      {:ok, metrics} = MedlumLlm.Telemetry.Metrics.calculate_model_metrics("exp_123")
      metrics[:biomistral_7b].accuracy
      # => 0.612
  """
  @spec calculate_model_metrics(String.t(), keyword()) ::
          {:ok, %{atom() => model_metrics()}} | {:error, :no_data}
  def calculate_model_metrics(experiment_id, opts \\ []) do
    confidence_level = Keyword.get(opts, :confidence_level, 0.95)
    events = Store.get_all(experiment_id)

    sample_stop_events =
      Enum.filter(events, fn e ->
        e.event_name == [:medlum_llm, :eval, :sample, :stop]
      end)

    sample_exception_events =
      Enum.filter(events, fn e ->
        e.event_name == [:medlum_llm, :eval, :sample, :exception]
      end)

    if Enum.empty?(sample_stop_events) and Enum.empty?(sample_exception_events) do
      {:error, :no_data}
    else
      {:ok, do_calculate_model_metrics(sample_stop_events, sample_exception_events, confidence_level)}
    end
  end

  # Private implementation

  defp do_calculate_cvl_metrics(events) do
    total = length(events)

    # Count by verdict
    entailment_count = count_verdict(events, :entailment)
    contradiction_count = count_verdict(events, :contradiction)
    neutral_count = count_verdict(events, :neutral)

    # Calculate hallucination detection metrics
    # Hallucination detected = contradiction or neutral (not entailment)
    {precision, recall, f1} = calculate_hallucination_metrics(events)

    # Agent agreement rate (events with zero disagreements)
    agreement_count =
      Enum.count(events, fn e ->
        get_in(e, [:metadata, :disagreement_count]) == 0
      end)

    agreement_rate = if total > 0, do: agreement_count / total, else: 0.0

    # Mean verification latency
    latencies =
      events
      |> Enum.map(& &1.latency_ms)
      |> Enum.reject(&is_nil/1)

    mean_latency = if Enum.empty?(latencies), do: 0.0, else: Enum.sum(latencies) / length(latencies)

    # CVL accuracy: proportion of correct verdicts
    # If we have ground truth, use it; otherwise assume entailment is the target
    # For now, return the entailment rate as a proxy
    cvl_accuracy = if total > 0, do: entailment_count / total, else: 0.0

    %{
      cvl_accuracy: cvl_accuracy,
      hallucination_precision: precision,
      hallucination_recall: recall,
      hallucination_f1: f1,
      agent_agreement_rate: agreement_rate,
      mean_verification_latency_ms: mean_latency,
      total_verifications: total,
      entailment_count: entailment_count,
      contradiction_count: contradiction_count,
      neutral_count: neutral_count
    }
  end

  defp count_verdict(events, verdict) do
    Enum.count(events, fn e ->
      get_in(e, [:metadata, :verdict]) == verdict
    end)
  end

  defp calculate_hallucination_metrics(events) do
    # Hallucination detected = metadata.hallucination_detected == true
    # Ground truth = verdict in [:contradiction, :neutral]

    true_positives =
      Enum.count(events, fn e ->
        detected = get_in(e, [:metadata, :hallucination_detected]) == true
        actual = get_in(e, [:metadata, :verdict]) in [:contradiction, :neutral]
        detected and actual
      end)

    false_positives =
      Enum.count(events, fn e ->
        detected = get_in(e, [:metadata, :hallucination_detected]) == true
        actual = get_in(e, [:metadata, :verdict]) == :entailment
        detected and actual
      end)

    false_negatives =
      Enum.count(events, fn e ->
        detected = get_in(e, [:metadata, :hallucination_detected]) != true
        actual = get_in(e, [:metadata, :verdict]) in [:contradiction, :neutral]
        detected and actual
      end)

    precision =
      if true_positives + false_positives > 0 do
        true_positives / (true_positives + false_positives)
      else
        0.0
      end

    recall =
      if true_positives + false_negatives > 0 do
        true_positives / (true_positives + false_negatives)
      else
        0.0
      end

    f1 =
      if precision + recall > 0 do
        2 * precision * recall / (precision + recall)
      else
        0.0
      end

    {precision, recall, f1}
  end

  defp do_calculate_model_metrics(stop_events, exception_events, confidence_level) do
    # Group by model
    by_model = Enum.group_by(stop_events, fn e -> get_in(e, [:metadata, :model]) end)

    exception_by_model =
      Enum.group_by(exception_events, fn e -> get_in(e, [:metadata, :model]) end)

    # Calculate metrics for each model
    for {model, model_events} <- by_model, model != nil, into: %{} do
      model_exceptions = Map.get(exception_by_model, model, [])
      metrics = calculate_single_model_metrics(model, model_events, model_exceptions, confidence_level)
      {model, metrics}
    end
  end

  defp calculate_single_model_metrics(model, events, exceptions, confidence_level) do
    total = length(events)
    errors = length(exceptions)

    correct_count =
      Enum.count(events, fn e ->
        get_in(e, [:metadata, :correct]) == true
      end)

    accuracy = if total > 0, do: correct_count / total, else: 0.0

    # Wilson score CI (if CrucibleBench is available)
    {ci_lower, ci_upper} = calculate_wilson_ci(correct_count, total, confidence_level)

    # Latency percentiles
    latencies =
      events
      |> Enum.map(& &1.latency_ms)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    p50 = percentile(latencies, 50)
    p95 = percentile(latencies, 95)

    # Tokens per second
    tps_values =
      events
      |> Enum.map(fn e ->
        measurements = Map.get(e, :measurements, %{})
        Map.get(measurements, :tokens_per_second)
      end)
      |> Enum.reject(&is_nil/1)

    mean_tps = if Enum.empty?(tps_values), do: nil, else: Enum.sum(tps_values) / length(tps_values)

    %{
      model: model,
      accuracy: accuracy,
      accuracy_ci_lower: ci_lower,
      accuracy_ci_upper: ci_upper,
      total_samples: total,
      correct: correct_count,
      errors: errors,
      latency_p50: p50,
      latency_p95: p95,
      tokens_per_second: mean_tps
    }
  end

  defp calculate_wilson_ci(successes, total, confidence_level) when total > 0 do
    # Try to use CrucibleBench if available
    if Code.ensure_loaded?(CrucibleBench) and function_exported?(CrucibleBench, :wilson_score, 3) do
      case apply(CrucibleBench, :wilson_score, [successes, total, confidence_level]) do
        %{interval: {lower, upper}} -> {lower, upper}
        _ -> {nil, nil}
      end
    else
      # Fallback: no CI without CrucibleBench
      {nil, nil}
    end
  end

  defp calculate_wilson_ci(_successes, _total, _confidence_level), do: {nil, nil}

  defp percentile([], _p), do: nil

  defp percentile(sorted_values, p) when p >= 0 and p <= 100 do
    count = length(sorted_values)
    index = p / 100 * (count - 1)

    lower = floor(index)
    upper = ceil(index)

    if lower == upper do
      Enum.at(sorted_values, round(index))
    else
      lower_value = Enum.at(sorted_values, lower)
      upper_value = Enum.at(sorted_values, upper)
      fraction = index - lower
      lower_value + (upper_value - lower_value) * fraction
    end
  end
end
