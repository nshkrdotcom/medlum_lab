defmodule MedlumLlm.Eval.CvlMetrics do
  @moduledoc """
  Clinical Verification Layer (CVL) evaluation metrics.

  CVL is MedlumLlm's multi-agent verification system that classifies claims
  using 3-way NLI classification:

  - **ENTAILMENT**: Claim supported by evidence (not flagged)
  - **CONTRADICTION**: Claim conflicts with evidence (flagged)
  - **NEUTRAL**: Claim cannot be verified (flagged as potentially hallucinated)

  ## Hallucination Detection

  In the medical context, both CONTRADICTION and NEUTRAL are treated as
  hallucination flags because:

  - CONTRADICTION: Direct conflict with evidence is dangerous
  - NEUTRAL: Ungrounded claims could be fabricated (dangerous in medical context)

  ## Target Metrics

  - **Hallucination Recall**: >95% (safety-critical: don't miss real hallucinations)
  - **Hallucination Precision**: >85% (usability: minimize false alarms)

  ## Multi-Agent Architecture

  CVL uses 5 specialized verification agents:

  1. **Medication Agent** (RxNorm) - Drug name, dose, frequency
  2. **Lab Agent** (LOINC) - Lab values, reference ranges
  3. **Ontology Agent** - SNOMED-CT/ICD-10 consistency
  4. **Temporal Agent** - Timeline and progression logic
  5. **Differential Diagnosis Agent** - Symptom-diagnosis mapping

  ## Example

      # CVL predictions with verdicts
      predictions = [
        %{sample_id: 1, verdict: :entailment, confidence: 0.95},
        %{sample_id: 2, verdict: :contradiction, confidence: 0.88},
        %{sample_id: 3, verdict: :neutral, confidence: 0.72}
      ]

      # Ground truth labels
      ground_truth = [
        %{sample_id: 1, is_hallucination: false},
        %{sample_id: 2, is_hallucination: true},
        %{sample_id: 3, is_hallucination: true}
      ]

      MedlumLlm.Eval.CvlMetrics.hallucination_recall(predictions, ground_truth)
      # => 1.0 (all hallucinations caught)

      MedlumLlm.Eval.CvlMetrics.hallucination_precision(predictions, ground_truth)
      # => 1.0 (all flags were actual hallucinations)
  """

  @verdicts [:entailment, :contradiction, :neutral]
  @flagged_verdicts [:contradiction, :neutral]

  # ============================================================================
  # Hallucination Detection Metrics
  # ============================================================================

  @doc """
  Calculate hallucination detection recall (sensitivity).

  Recall = Caught Hallucinations / Total Actual Hallucinations

  NEUTRAL and CONTRADICTION are both considered "flagged" because in medical
  contexts, both represent potentially dangerous claims:
  - CONTRADICTION: Directly conflicts with evidence
  - NEUTRAL: Cannot be verified, could be fabricated

  ## Target

  >95% recall is critical for patient safety. Missing a hallucination could
  lead to incorrect medical decisions.

  ## Parameters

    * `cvl_predictions` - List of `%{sample_id: term(), verdict: atom()}`
    * `ground_truth` - List of `%{sample_id: term(), is_hallucination: boolean()}`

  ## Returns

  Float from 0.0 to 1.0 representing recall.

  ## Edge Cases

  - Returns 1.0 when no actual hallucinations exist (perfect recall by definition)

  ## Examples

      iex> preds = [
      ...>   %{sample_id: 1, verdict: :contradiction},
      ...>   %{sample_id: 2, verdict: :neutral},
      ...>   %{sample_id: 3, verdict: :entailment}
      ...> ]
      iex> truth = [
      ...>   %{sample_id: 1, is_hallucination: true},
      ...>   %{sample_id: 2, is_hallucination: true},
      ...>   %{sample_id: 3, is_hallucination: false}
      ...> ]
      iex> MedlumLlm.Eval.CvlMetrics.hallucination_recall(preds, truth)
      1.0

  """
  @spec hallucination_recall([map()], [map()]) :: float()
  def hallucination_recall(cvl_predictions, ground_truth)
      when is_list(cvl_predictions) and is_list(ground_truth) do
    actual_hallucinations = Enum.filter(ground_truth, & &1.is_hallucination)

    if Enum.empty?(actual_hallucinations) do
      # Perfect recall when nothing to detect
      1.0
    else
      caught =
        Enum.count(actual_hallucinations, fn gt ->
          pred = Enum.find(cvl_predictions, &(&1.sample_id == gt.sample_id))
          pred && pred.verdict in @flagged_verdicts
        end)

      caught / length(actual_hallucinations)
    end
  end

  @doc """
  Calculate hallucination detection precision.

  Precision = True Flags / Total Flags

  A true flag is when the system flags a sample (CONTRADICTION or NEUTRAL)
  and it actually is a hallucination.

  ## Target

  >85% precision is important for usability. Too many false alarms create
  alert fatigue, causing clinicians to ignore real warnings.

  ## Parameters

    * `cvl_predictions` - List of `%{sample_id: term(), verdict: atom()}`
    * `ground_truth` - List of `%{sample_id: term(), is_hallucination: boolean()}`

  ## Returns

  Float from 0.0 to 1.0 representing precision.

  ## Edge Cases

  - Returns 1.0 when nothing is flagged (no false positives possible)

  ## Examples

      iex> preds = [
      ...>   %{sample_id: 1, verdict: :contradiction},
      ...>   %{sample_id: 2, verdict: :entailment}
      ...> ]
      iex> truth = [
      ...>   %{sample_id: 1, is_hallucination: true},
      ...>   %{sample_id: 2, is_hallucination: false}
      ...> ]
      iex> MedlumLlm.Eval.CvlMetrics.hallucination_precision(preds, truth)
      1.0

  """
  @spec hallucination_precision([map()], [map()]) :: float()
  def hallucination_precision(cvl_predictions, ground_truth)
      when is_list(cvl_predictions) and is_list(ground_truth) do
    flagged_predictions = Enum.filter(cvl_predictions, &(&1.verdict in @flagged_verdicts))

    if Enum.empty?(flagged_predictions) do
      # Perfect precision when nothing is flagged (no false positives)
      1.0
    else
      true_flags =
        Enum.count(flagged_predictions, fn pred ->
          gt = Enum.find(ground_truth, &(&1.sample_id == pred.sample_id))
          gt && gt.is_hallucination
        end)

      true_flags / length(flagged_predictions)
    end
  end

  @doc """
  Calculate hallucination detection F1 score.

  F1 = 2 * (Precision * Recall) / (Precision + Recall)

  F1 balances recall (safety) and precision (usability). In medical contexts,
  recall is often prioritized, but F1 provides a single balanced metric.

  ## Parameters

    * `cvl_predictions` - List of `%{sample_id: term(), verdict: atom()}`
    * `ground_truth` - List of `%{sample_id: term(), is_hallucination: boolean()}`

  ## Returns

  Float from 0.0 to 1.0 representing F1 score.

  ## Examples

      iex> preds = [%{sample_id: 1, verdict: :contradiction}]
      iex> truth = [%{sample_id: 1, is_hallucination: true}]
      iex> MedlumLlm.Eval.CvlMetrics.hallucination_f1(preds, truth)
      1.0

  """
  @spec hallucination_f1([map()], [map()]) :: float()
  def hallucination_f1(cvl_predictions, ground_truth)
      when is_list(cvl_predictions) and is_list(ground_truth) do
    recall = hallucination_recall(cvl_predictions, ground_truth)
    precision = hallucination_precision(cvl_predictions, ground_truth)

    if recall + precision > 0 do
      2 * (recall * precision) / (recall + precision)
    else
      0.0
    end
  end

  @doc """
  Generate confusion matrix for hallucination detection.

  Provides detailed breakdown of true/false positives and negatives
  for binary hallucination classification.

  ## Parameters

    * `cvl_predictions` - List of `%{sample_id: term(), verdict: atom()}`
    * `ground_truth` - List of `%{sample_id: term(), is_hallucination: boolean()}`

  ## Returns

  Map with confusion matrix components:

      %{
        true_positive: integer(),   # Flagged and actually hallucination
        false_positive: integer(),  # Flagged but not hallucination
        true_negative: integer(),   # Not flagged and not hallucination
        false_negative: integer()   # Not flagged but actually hallucination
      }

  ## Examples

      iex> preds = [
      ...>   %{sample_id: 1, verdict: :contradiction},
      ...>   %{sample_id: 2, verdict: :entailment}
      ...> ]
      iex> truth = [
      ...>   %{sample_id: 1, is_hallucination: true},
      ...>   %{sample_id: 2, is_hallucination: false}
      ...> ]
      iex> MedlumLlm.Eval.CvlMetrics.hallucination_confusion_matrix(preds, truth)
      %{true_positive: 1, false_positive: 0, true_negative: 1, false_negative: 0}

  """
  @spec hallucination_confusion_matrix([map()], [map()]) :: map()
  def hallucination_confusion_matrix(cvl_predictions, ground_truth)
      when is_list(cvl_predictions) and is_list(ground_truth) do
    # Build lookup map for predictions
    pred_map =
      cvl_predictions
      |> Enum.map(fn p -> {p.sample_id, p.verdict in @flagged_verdicts} end)
      |> Map.new()

    Enum.reduce(ground_truth, %{tp: 0, fp: 0, tn: 0, fn: 0}, fn gt, acc ->
      flagged = Map.get(pred_map, gt.sample_id, false)
      classify_confusion_outcome(acc, flagged, gt.is_hallucination)
    end)
    |> rename_confusion_keys()
  end

  defp classify_confusion_outcome(acc, true, true), do: %{acc | tp: acc.tp + 1}
  defp classify_confusion_outcome(acc, true, false), do: %{acc | fp: acc.fp + 1}
  defp classify_confusion_outcome(acc, false, false), do: %{acc | tn: acc.tn + 1}
  defp classify_confusion_outcome(acc, false, true), do: %{acc | fn: acc.fn + 1}

  defp rename_confusion_keys(counts) do
    %{
      true_positive: counts.tp,
      false_positive: counts.fp,
      true_negative: counts.tn,
      false_negative: counts.fn
    }
  end

  # ============================================================================
  # Calibration Error
  # ============================================================================

  @doc """
  Calculate Expected Calibration Error (ECE).

  Measures how well confidence scores match actual accuracy. A well-calibrated
  model should have confidence scores that reflect true probabilities.

  For example, predictions with 90% confidence should be correct ~90% of the time.

  ## Algorithm

  1. Group predictions into bins by confidence (default: 10 bins)
  2. For each bin, calculate average confidence and actual accuracy
  3. ECE = weighted sum of |confidence - accuracy| for each bin

  ## Parameters

    * `predictions` - List of `%{verdict: atom(), confidence: float()}`
    * `samples` - List of `%{label: atom()}` (ground truth labels)
    * `opts` - Options
      - `:bins` - Number of confidence bins (default: 10)

  ## Returns

  Float from 0.0 to 1.0 (lower is better, 0.0 = perfectly calibrated).

  ## Examples

      iex> preds = [
      ...>   %{verdict: :entailment, confidence: 0.9},
      ...>   %{verdict: :entailment, confidence: 0.9}
      ...> ]
      iex> samples = [
      ...>   %{label: :entailment},
      ...>   %{label: :entailment}
      ...> ]
      iex> MedlumLlm.Eval.CvlMetrics.calibration_error(preds, samples)
      0.0

  """
  @spec calibration_error([map()], [map()], keyword()) :: float()
  def calibration_error(predictions, samples, opts \\ [])

  def calibration_error(predictions, samples, opts)
      when is_list(predictions) and is_list(samples) do
    n_bins = Keyword.get(opts, :bins, 10)

    if Enum.empty?(predictions) or Enum.empty?(samples) do
      0.0
    else
      paired =
        predictions
        |> Enum.zip(samples)
        |> Enum.map(fn {pred, sample} ->
          %{
            confidence: Map.get(pred, :confidence, 1.0),
            correct: pred.verdict == sample.label
          }
        end)

      # Group by confidence bins
      bins =
        Enum.group_by(paired, fn item ->
          min(floor(item.confidence * n_bins), n_bins - 1)
        end)

      # Calculate ECE
      total = length(paired)

      Enum.reduce(bins, 0.0, fn {_bin, items}, acc ->
        avg_conf = mean(Enum.map(items, & &1.confidence))
        accuracy = Enum.count(items, & &1.correct) / length(items)
        weight = length(items) / total
        acc + weight * abs(avg_conf - accuracy)
      end)
    end
  end

  # ============================================================================
  # Multi-Agent Metrics
  # ============================================================================

  @doc """
  Calculate average agreement rate across CVL agents.

  Agreement rate measures how often all agents agree on the verdict.
  Higher agreement suggests more confident classifications.

  ## Target

  >80% agreement rate indicates good consensus among agents.

  ## Parameters

    * `agent_predictions` - Map of `%{sample_id => %{agent1: verdict, agent2: verdict, ...}}`

  ## Returns

  Float from 0.0 to 1.0 (1.0 = all agents always agree).

  ## Examples

      iex> agent_preds = %{
      ...>   1 => %{med: :entailment, lab: :entailment, ont: :entailment},
      ...>   2 => %{med: :contradiction, lab: :contradiction, ont: :neutral}
      ...> }
      iex> rate = MedlumLlm.Eval.CvlMetrics.agent_agreement_rate(agent_preds)
      iex> rate > 0.5
      true

  """
  @spec agent_agreement_rate(map()) :: float()
  def agent_agreement_rate(agent_predictions) when is_map(agent_predictions) do
    if Enum.empty?(agent_predictions) do
      1.0
    else
      agent_predictions
      |> Enum.map(fn {_sample_id, agent_verdicts} ->
        calculate_sample_agreement(Map.values(agent_verdicts))
      end)
      |> mean()
    end
  end

  defp calculate_sample_agreement([]), do: 1.0

  defp calculate_sample_agreement(verdicts) do
    num_agents = length(verdicts)
    max_count = verdicts |> Enum.frequencies() |> Map.values() |> Enum.max()
    max_count / num_agents
  end

  @doc """
  Calculate accuracy of majority vote consensus.

  Uses majority voting across agents to determine the final verdict,
  then compares against ground truth.

  ## Parameters

    * `agent_predictions` - Map of `%{sample_id => %{agent1: verdict, ...}}`
    * `ground_truth` - List of `%{sample_id: term(), label: atom()}`

  ## Returns

  Float from 0.0 to 1.0 representing consensus accuracy.

  ## Examples

      iex> agent_preds = %{
      ...>   1 => %{med: :entailment, lab: :entailment, ont: :entailment}
      ...> }
      iex> truth = [%{sample_id: 1, label: :entailment}]
      iex> MedlumLlm.Eval.CvlMetrics.consensus_accuracy(agent_preds, truth)
      1.0

  """
  @spec consensus_accuracy(map(), [map()]) :: float()
  def consensus_accuracy(agent_predictions, ground_truth)
      when is_map(agent_predictions) and is_list(ground_truth) do
    if Enum.empty?(ground_truth) do
      0.0
    else
      correct =
        Enum.count(ground_truth, fn gt ->
          check_consensus_match(agent_predictions, gt)
        end)

      correct / length(ground_truth)
    end
  end

  defp check_consensus_match(agent_predictions, gt) do
    case Map.get(agent_predictions, gt.sample_id) do
      nil -> false
      agent_verdicts -> majority_vote(Map.values(agent_verdicts)) == gt.label
    end
  end

  @doc """
  Calculate accuracy for each individual agent.

  Provides per-agent performance metrics to identify strong/weak agents.

  ## Parameters

    * `agent_predictions` - Map of `%{sample_id => %{agent1: verdict, ...}}`
    * `ground_truth` - List of `%{sample_id: term(), label: atom()}`

  ## Returns

  Map of agent_name => accuracy float.

  ## Examples

      iex> agent_preds = %{
      ...>   1 => %{med: :entailment, lab: :entailment},
      ...>   2 => %{med: :contradiction, lab: :entailment}
      ...> }
      iex> truth = [
      ...>   %{sample_id: 1, label: :entailment},
      ...>   %{sample_id: 2, label: :contradiction}
      ...> ]
      iex> result = MedlumLlm.Eval.CvlMetrics.per_agent_accuracy(agent_preds, truth)
      iex> result[:med]
      1.0
      iex> result[:lab]
      0.5

  """
  @spec per_agent_accuracy(map(), [map()]) :: map()
  def per_agent_accuracy(agent_predictions, ground_truth)
      when is_map(agent_predictions) and is_list(ground_truth) do
    if Enum.empty?(agent_predictions) or Enum.empty?(ground_truth) do
      %{}
    else
      agent_names = extract_agent_names(agent_predictions)
      gt_map = build_ground_truth_map(ground_truth)
      calculate_all_agent_accuracies(agent_predictions, agent_names, gt_map)
    end
  end

  defp extract_agent_names(agent_predictions) do
    agent_predictions |> Map.values() |> List.first() |> Map.keys()
  end

  defp build_ground_truth_map(ground_truth) do
    ground_truth |> Enum.map(fn gt -> {gt.sample_id, gt.label} end) |> Map.new()
  end

  defp calculate_all_agent_accuracies(agent_predictions, agent_names, gt_map) do
    Enum.reduce(agent_names, %{}, fn agent, acc ->
      accuracy = calculate_single_agent_accuracy(agent_predictions, agent, gt_map)
      Map.put(acc, agent, accuracy)
    end)
  end

  defp calculate_single_agent_accuracy(agent_predictions, agent, gt_map) do
    correct_count =
      Enum.count(agent_predictions, fn {sample_id, agent_verdicts} ->
        Map.get(agent_verdicts, agent) == Map.get(gt_map, sample_id)
      end)

    correct_count / map_size(agent_predictions)
  end

  @doc """
  Analyze agent performance when there is disagreement.

  Identifies which agents perform best when the ensemble disagrees,
  useful for debugging and improving individual agents.

  ## Parameters

    * `agent_predictions` - Map of `%{sample_id => %{agent1: verdict, ...}}`
    * `ground_truth` - List of `%{sample_id: term(), label: atom()}`

  ## Returns

  Map with analysis results:

      %{
        disagreement_count: integer(),
        per_agent_accuracy: %{agent => float()},
        consensus_accuracy: float()
      }

  ## Examples

      iex> agent_preds = %{
      ...>   1 => %{med: :entailment, lab: :contradiction}
      ...> }
      iex> truth = [%{sample_id: 1, label: :entailment}]
      iex> result = MedlumLlm.Eval.CvlMetrics.disagreement_analysis(agent_preds, truth)
      iex> result.disagreement_count
      1

  """
  @spec disagreement_analysis(map(), [map()]) :: map()
  def disagreement_analysis(agent_predictions, ground_truth)
      when is_map(agent_predictions) and is_list(ground_truth) do
    # Filter to only samples with disagreement
    disagreement_samples =
      Enum.filter(agent_predictions, fn {_sample_id, agent_verdicts} ->
        verdicts = Map.values(agent_verdicts)
        length(Enum.uniq(verdicts)) > 1
      end)
      |> Map.new()

    disagreement_sample_ids = Map.keys(disagreement_samples)

    # Filter ground truth to disagreement samples
    disagreement_truth =
      Enum.filter(ground_truth, fn gt ->
        gt.sample_id in disagreement_sample_ids
      end)

    %{
      disagreement_count: length(disagreement_sample_ids),
      per_agent_accuracy: per_agent_accuracy(disagreement_samples, disagreement_truth),
      consensus_accuracy: consensus_accuracy(disagreement_samples, disagreement_truth)
    }
  end

  # ============================================================================
  # NLI Verdict Helpers
  # ============================================================================

  @doc """
  Get the list of valid CVL verdicts.

  ## Returns

  List of atoms: `[:entailment, :contradiction, :neutral]`
  """
  @spec valid_verdicts() :: [atom()]
  def valid_verdicts, do: @verdicts

  @doc """
  Get the list of verdicts that are considered "flagged" (potential hallucinations).

  ## Returns

  List of atoms: `[:contradiction, :neutral]`
  """
  @spec flagged_verdicts() :: [atom()]
  def flagged_verdicts, do: @flagged_verdicts

  @doc """
  Check if a verdict is flagged as a potential hallucination.

  ## Parameters

    * `verdict` - The verdict atom to check

  ## Returns

  Boolean indicating if the verdict is flagged.

  ## Examples

      iex> MedlumLlm.Eval.CvlMetrics.flagged?(:entailment)
      false

      iex> MedlumLlm.Eval.CvlMetrics.flagged?(:contradiction)
      true

      iex> MedlumLlm.Eval.CvlMetrics.flagged?(:neutral)
      true

  """
  @spec flagged?(atom()) :: boolean()
  def flagged?(verdict) when is_atom(verdict), do: verdict in @flagged_verdicts

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp mean([]), do: 0.0

  defp mean(values) when is_list(values) do
    Enum.sum(values) / length(values)
  end

  defp majority_vote([]), do: nil

  defp majority_vote(verdicts) when is_list(verdicts) do
    verdicts
    |> Enum.frequencies()
    |> Enum.max_by(fn {_verdict, count} -> count end)
    |> elem(0)
  end
end
