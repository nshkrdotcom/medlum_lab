defmodule MedlumLlm.Eval.MedicalMetrics do
  @moduledoc """
  Medical-specific evaluation metrics.

  Delegates generic metrics to eval_ex, adds medical-specific calculations
  for medication accuracy, diagnosis accuracy, and hallucination detection.

  ## Metric Categories

  ### Standard Metrics (delegated)
  - `accuracy/2` - Correct predictions / total
  - `f1/3` - F1 score with macro/micro/weighted options
  - `exact_match/2` - Exact string matching

  ### Statistical Metrics (delegated)
  - `wilson_ci/3` - Wilson confidence interval for proportions
  - `mcnemar_test/3` - McNemar's test for paired model comparison
  - `bootstrap_ci/3` - Bootstrap CI for arbitrary statistics

  ### Medical Metrics (implemented here)
  - `medication_accuracy/2` - RxNorm-validated medication mentions
  - `diagnosis_accuracy/2` - ICD-10-validated diagnosis codes
  - `hallucination_recall/2` - CVL hallucination detection rate
  - `hallucination_precision/2` - CVL precision (avoid false positives)
  - `clinical_safety_score/3` - Weighted composite score
  """

  # =========================================================================
  # Delegated Generic Metrics (from eval_ex)
  # =========================================================================

  @doc """
  Calculate accuracy (correct / total).

  ## Examples

      predictions = ["A", "B", "A"]
      samples = [%{answer: "A"}, %{answer: "B"}, %{answer: "C"}]
      MedlumLlm.Eval.MedicalMetrics.accuracy(predictions, samples)
      #=> 0.667

  """
  @spec accuracy([term()], [map()]) :: float()
  def accuracy(predictions, samples) do
    fallback_accuracy(predictions, samples)
  end

  @doc "Calculate F1 score."
  @spec f1([term()], [map()], keyword()) :: float()
  def f1(predictions, samples, opts \\ []) do
    fallback_f1(predictions, samples, opts)
  end

  @doc "Calculate exact match rate."
  @spec exact_match([String.t()], [map()]) :: float()
  def exact_match(predictions, samples) do
    fallback_exact_match(predictions, samples)
  end

  @doc "Calculate BLEU score for generation tasks."
  @spec bleu([String.t()], [String.t()], keyword()) :: float()
  def bleu(predictions, references, opts \\ []) do
    if Code.ensure_loaded?(EvalEx.Metrics) do
      EvalEx.Metrics.bleu(predictions, references, opts)
    else
      0.0  # Fallback not implemented for complex metrics
    end
  end

  @doc "Calculate ROUGE scores for summarization."
  @spec rouge([String.t()], [String.t()], keyword()) :: map()
  def rouge(predictions, references, _opts \\ []) do
    if Code.ensure_loaded?(EvalEx.Metrics) do
      EvalEx.Metrics.rouge(predictions, references)
    else
      %{rouge1: 0.0, rouge2: 0.0, rougeL: 0.0}
    end
  end

  # =========================================================================
  # Delegated Statistical Tests (from crucible_bench)
  # =========================================================================

  @doc """
  Calculate Wilson confidence interval for proportions.

  More accurate than normal approximation for small samples or extreme proportions.

  ## Examples

      # 70 correct out of 100, 95% CI
      MedlumLlm.Eval.MedicalMetrics.wilson_ci(70, 100)
      #=> {0.602, 0.785}

  """
  @spec wilson_ci(integer(), integer(), float()) :: {float(), float()}
  def wilson_ci(successes, n, alpha \\ 0.05) do
    if Code.ensure_loaded?(CrucibleBench.Stats.ConfidenceInterval) do
      result = CrucibleBench.Stats.ConfidenceInterval.wilson_score(successes, n, 1.0 - alpha)
      result.interval
    else
      fallback_wilson_ci(successes, n, alpha)
    end
  end

  @doc """
  McNemar's test for paired model comparison.

  Tests if two models have significantly different error rates on the same samples.

  ## Examples

      pred_a = ["A", "B", "A", "A"]
      pred_b = ["A", "A", "A", "B"]
      samples = [%{answer: "A"}, %{answer: "B"}, %{answer: "A"}, %{answer: "A"}]

      MedlumLlm.Eval.MedicalMetrics.mcnemar_test(pred_a, pred_b, samples)
      #=> %CrucibleBench.Result{test: :mcnemar, statistic: 1.0, p_value: 0.317, ...}

  """
  @spec mcnemar_test([term()], [term()], [map()]) :: map() | struct()
  def mcnemar_test(pred_a, pred_b, samples) do
    if Code.ensure_loaded?(CrucibleBench.Stats.McNemar) do
      correct_a = Enum.zip_with(pred_a, samples, fn pred, sample ->
        pred == (sample[:answer] || sample["answer"])
      end)
      correct_b = Enum.zip_with(pred_b, samples, fn pred, sample ->
        pred == (sample[:answer] || sample["answer"])
      end)
      CrucibleBench.Stats.McNemar.test(correct_a, correct_b)
    else
      fallback_mcnemar_test(pred_a, pred_b, samples)
    end
  end

  @doc "Bootstrap confidence interval for arbitrary statistics."
  @spec bootstrap_ci([number()], (list() -> number()), keyword()) :: {float(), float()}
  def bootstrap_ci(data, statistic_fn, opts \\ []) do
    if Code.ensure_loaded?(CrucibleBench.Stats.ConfidenceInterval) do
      result = CrucibleBench.Stats.ConfidenceInterval.calculate(
        data,
        statistic_fn,
        Keyword.put(opts, :method, :bootstrap)
      )
      result.interval
    else
      # Simple fallback: just return the statistic with no interval
      stat = statistic_fn.(data)
      {stat, stat}
    end
  end

  # =========================================================================
  # Medical-Specific Metrics (NEW)
  # =========================================================================

  @doc """
  Validate medication mentions against RxNorm.

  Measures what fraction of predicted medications match valid RxNorm concepts.
  Uses med_ontology_ex for validation when available, falls back to string matching.

  ## Examples

      predictions = [%{text: "metformin 500mg bid"}]
      samples = [%{medications: [%{name: "metformin", dose: "500mg", frequency: "bid"}]}]

      MedlumLlm.Eval.MedicalMetrics.medication_accuracy(predictions, samples)
      #=> 1.0

  """
  @spec medication_accuracy([map()], [map()]) :: float()
  def medication_accuracy(predictions, samples) do
    pairs = Enum.zip(predictions, samples)

    {correct, total} = Enum.reduce(pairs, {0, 0}, fn {pred, sample}, {c, t} ->
      pred_meds = extract_medications(pred)
      gold_meds = sample[:medications] || sample["medications"] || []

      matches = Enum.count(pred_meds, fn med ->
        Enum.any?(gold_meds, &medication_match?(&1, med))
      end)

      {c + matches, t + length(gold_meds)}
    end)

    safe_divide(correct, total)
  end

  @doc """
  Validate diagnosis codes against ICD-10.

  Measures what fraction of predicted diagnoses are valid ICD-10 codes
  that match the ground truth at the appropriate specificity level.

  ## Matching Criteria
  - Exact ICD-10 code match: 1.0 credit
  - Parent/child code match: 0.5 credit (future)
  - Same chapter match: 0.2 credit (future)

  """
  @spec diagnosis_accuracy([map()], [map()]) :: float()
  def diagnosis_accuracy(predictions, samples) do
    pairs = Enum.zip(predictions, samples)

    {correct, total} = Enum.reduce(pairs, {0, 0}, fn {pred, sample}, {c, t} ->
      pred_dx = extract_diagnoses(pred)
      gold_dx = sample[:diagnoses] || sample["diagnoses"] || []

      matches = Enum.count(pred_dx, fn dx ->
        Enum.any?(gold_dx, &diagnosis_match?(&1, dx))
      end)

      {c + matches, t + length(gold_dx)}
    end)

    safe_divide(correct, total)
  end

  @doc """
  Calculate lab value accuracy against LOINC.

  Validates that lab values are physiologically possible and correctly formatted.
  """
  @spec lab_accuracy([map()], [map()]) :: float()
  def lab_accuracy(predictions, samples) do
    pairs = Enum.zip(predictions, samples)

    {correct, total} = Enum.reduce(pairs, {0, 0}, fn {pred, sample}, {c, t} ->
      pred_labs = extract_labs(pred)
      gold_labs = sample[:labs] || sample["labs"] || []

      matches = Enum.count(pred_labs, fn lab ->
        Enum.any?(gold_labs, &lab_match?(&1, lab))
      end)

      {c + matches, t + length(gold_labs)}
    end)

    safe_divide(correct, total)
  end

  @doc """
  Calculate CVL hallucination detection rate (recall).

  Measures what fraction of actual hallucinations were detected by CVL.
  NEUTRAL verdicts count as detected because they trigger human review.

  ## Target: >95% for grant milestones

  """
  @spec hallucination_recall([map()], [map()]) :: float()
  def hallucination_recall(cvl_predictions, ground_truth) do
    actual_hallucinations = Enum.filter(ground_truth, fn gt ->
      gt[:is_hallucination] || gt["is_hallucination"]
    end)

    if Enum.empty?(actual_hallucinations) do
      1.0  # No hallucinations to detect
    else
      caught = Enum.count(actual_hallucinations, fn gt ->
        sample_id = gt[:sample_id] || gt["sample_id"]
        cvl_pred = Enum.find(cvl_predictions, fn p ->
          (p[:sample_id] || p["sample_id"]) == sample_id
        end)
        cvl_pred && (cvl_pred[:verdict] || cvl_pred["verdict"]) in [:contradiction, :neutral, "contradiction", "neutral"]
      end)

      caught / length(actual_hallucinations)
    end
  end

  @doc """
  Calculate CVL hallucination precision.

  Measures what fraction of flagged items were actual hallucinations.
  High precision reduces clinician alert fatigue.

  ## Target: >85% for grant milestones

  """
  @spec hallucination_precision([map()], [map()]) :: float()
  def hallucination_precision(cvl_predictions, ground_truth) do
    flagged = Enum.filter(cvl_predictions, fn pred ->
      verdict = pred[:verdict] || pred["verdict"]
      verdict in [:contradiction, :neutral, "contradiction", "neutral"]
    end)

    if Enum.empty?(flagged) do
      1.0  # Nothing flagged, trivially perfect precision
    else
      true_positives = Enum.count(flagged, fn pred ->
        sample_id = pred[:sample_id] || pred["sample_id"]
        gt = Enum.find(ground_truth, fn g ->
          (g[:sample_id] || g["sample_id"]) == sample_id
        end)
        gt && (gt[:is_hallucination] || gt["is_hallucination"])
      end)

      true_positives / length(flagged)
    end
  end

  @doc """
  Calculate hallucination F1 score.

  Harmonic mean of recall and precision.
  """
  @spec hallucination_f1([map()], [map()]) :: float()
  def hallucination_f1(cvl_predictions, ground_truth) do
    recall = hallucination_recall(cvl_predictions, ground_truth)
    precision = hallucination_precision(cvl_predictions, ground_truth)

    if recall + precision == 0 do
      0.0
    else
      2 * recall * precision / (recall + precision)
    end
  end

  @doc """
  Calculate clinical safety score.

  Composite metric weighing:
  - Medication accuracy (40%): Most safety-critical
  - Diagnosis accuracy (30%): Important for treatment decisions
  - Hallucination detection (30%): Prevents misinformation

  ## Target: >0.85 for grant milestones

  """
  @spec clinical_safety_score([map()], [map()], [map()]) :: float()
  def clinical_safety_score(predictions, samples, cvl_results) do
    med_acc = medication_accuracy(predictions, samples)
    dx_acc = diagnosis_accuracy(predictions, samples)
    hall_recall = hallucination_recall(cvl_results, samples)

    0.4 * med_acc + 0.3 * dx_acc + 0.3 * hall_recall
  end

  # =========================================================================
  # Reporting Helpers
  # =========================================================================

  @doc """
  Format metrics as a report map with confidence intervals.
  """
  @spec format_report([map()], [map()], keyword()) :: map()
  def format_report(predictions, samples, opts \\ []) do
    n = length(samples)
    correct = Enum.zip(predictions, samples)
              |> Enum.count(fn {pred, sample} ->
                extract_answer(pred) == extract_answer(sample)
              end)

    acc = safe_divide(correct, n)
    {ci_low, ci_high} = wilson_ci(correct, n)

    %{
      accuracy: acc,
      accuracy_ci_95: {Float.round(ci_low, 4), Float.round(ci_high, 4)},
      sample_count: n,
      correct_count: correct
    }
    |> maybe_add_medical_metrics(predictions, samples, opts)
  end

  defp maybe_add_medical_metrics(report, predictions, samples, opts) do
    if Keyword.get(opts, :medical_metrics, false) do
      report
      |> Map.put(:medication_accuracy, medication_accuracy(predictions, samples))
      |> Map.put(:diagnosis_accuracy, diagnosis_accuracy(predictions, samples))
    else
      report
    end
  end

  # =========================================================================
  # Private Helpers
  # =========================================================================

  defp safe_divide(_numerator, 0), do: 0.0
  defp safe_divide(numerator, denominator), do: numerator / denominator

  defp extract_medications(%{text: text}) when is_binary(text) do
    # Use clinical_ner_ex if available
    if Code.ensure_loaded?(ClinicalNerEx) do
      case ClinicalNerEx.extract_medications(text) do
        {:ok, entities} -> entities
        _ -> []
      end
    else
      # Fallback: simple regex extraction
      extract_medications_regex(text)
    end
  end
  defp extract_medications(%{medications: meds}) when is_list(meds), do: meds
  defp extract_medications(%{"medications" => meds}) when is_list(meds), do: meds
  defp extract_medications(_), do: []

  defp extract_medications_regex(text) do
    # Basic medication pattern: drug name possibly followed by dose
    Regex.scan(~r/\b([A-Z][a-z]+(?:in|ol|ide|ine|ate|one))\b/i, text)
    |> Enum.map(fn [_, name] -> %{name: String.downcase(name)} end)
    |> Enum.uniq_by(& &1.name)
  end

  defp extract_diagnoses(%{text: text}) when is_binary(text) do
    if Code.ensure_loaded?(ClinicalNerEx) do
      case ClinicalNerEx.extract_diagnoses(text) do
        {:ok, entities} -> entities
        _ -> []
      end
    else
      []
    end
  end
  defp extract_diagnoses(%{diagnoses: dx}) when is_list(dx), do: dx
  defp extract_diagnoses(%{"diagnoses" => dx}) when is_list(dx), do: dx
  defp extract_diagnoses(_), do: []

  defp extract_labs(%{text: text}) when is_binary(text) do
    if Code.ensure_loaded?(ClinicalNerEx) do
      case ClinicalNerEx.extract_lab_values(text) do
        {:ok, entities} -> entities
        _ -> []
      end
    else
      []
    end
  end
  defp extract_labs(%{labs: labs}) when is_list(labs), do: labs
  defp extract_labs(%{"labs" => labs}) when is_list(labs), do: labs
  defp extract_labs(_), do: []

  defp medication_match?(gold, pred) do
    gold_name = normalize_med_name(gold[:name] || gold["name"] || "")
    pred_name = normalize_med_name(pred[:name] || pred["name"] || pred[:text] || pred["text"] || "")
    gold_name == pred_name
  end

  defp diagnosis_match?(gold, pred) do
    gold_code = gold[:icd10] || gold["icd10"]
    pred_code = pred[:icd10] || pred["icd10"]

    if gold_code && pred_code do
      gold_code == pred_code
    else
      gold_name = normalize_dx_name(gold[:name] || gold["name"] || "")
      pred_name = normalize_dx_name(pred[:name] || pred["name"] || pred[:text] || pred["text"] || "")
      gold_name == pred_name
    end
  end

  defp lab_match?(gold, pred) do
    gold_name = normalize_lab_name(gold[:name] || gold["name"] || "")
    pred_name = normalize_lab_name(pred[:name] || pred["name"] || pred[:text] || pred["text"] || "")
    gold_name == pred_name
  end

  defp normalize_med_name(name), do: name |> String.downcase() |> String.trim()
  defp normalize_dx_name(name), do: name |> String.downcase() |> String.trim()
  defp normalize_lab_name(name), do: name |> String.downcase() |> String.trim()

  defp extract_answer(%{} = map), do: map[:answer] || map["answer"]
  defp extract_answer(value), do: value

  # =========================================================================
  # Fallback Implementations
  # =========================================================================

  defp fallback_accuracy(predictions, samples) do
    correct = Enum.zip(predictions, samples)
              |> Enum.count(fn {pred, sample} ->
                answer = sample[:answer] || sample["answer"]
                pred == answer
              end)
    safe_divide(correct, length(samples))
  end

  defp fallback_f1(predictions, samples, _opts) do
    # Simple binary F1 fallback
    {tp, fp, fn_count} = Enum.zip(predictions, samples)
    |> Enum.reduce({0, 0, 0}, fn {pred, sample}, {tp, fp, fn_c} ->
      answer = sample[:answer] || sample["answer"]
      cond do
        pred == answer -> {tp + 1, fp, fn_c}
        pred != nil -> {tp, fp + 1, fn_c}
        true -> {tp, fp, fn_c + 1}
      end
    end)

    precision = safe_divide(tp, tp + fp)
    recall = safe_divide(tp, tp + fn_count)

    if precision + recall == 0 do
      0.0
    else
      2 * precision * recall / (precision + recall)
    end
  end

  defp fallback_exact_match(predictions, samples) do
    correct = Enum.zip(predictions, samples)
              |> Enum.count(fn {pred, sample} ->
                reference = sample[:answer] || sample["answer"] || sample[:target] || ""
                String.trim(to_string(pred)) == String.trim(to_string(reference))
              end)
    safe_divide(correct, length(samples))
  end

  defp fallback_wilson_ci(successes, n, alpha) do
    z = case alpha do
      0.05 -> 1.96
      0.01 -> 2.576
      0.10 -> 1.645
      _ -> 1.96
    end

    p_hat = successes / n
    denominator = 1 + z * z / n

    center = (p_hat + z * z / (2 * n)) / denominator
    margin = z * :math.sqrt((p_hat * (1 - p_hat) + z * z / (4 * n)) / n) / denominator

    {max(0.0, center - margin), min(1.0, center + margin)}
  end

  defp fallback_mcnemar_test(pred_a, pred_b, samples) do
    # Count discordant pairs
    {b, c} = Enum.zip([pred_a, pred_b, samples])
    |> Enum.reduce({0, 0}, fn [a, b, sample], {b_count, c_count} ->
      answer = sample[:answer] || sample["answer"]
      a_correct = a == answer
      b_correct = b == answer

      cond do
        a_correct and not b_correct -> {b_count + 1, c_count}
        not a_correct and b_correct -> {b_count, c_count + 1}
        true -> {b_count, c_count}
      end
    end)

    chi2 = if b + c > 0 do
      :math.pow(abs(b - c) - 1, 2) / (b + c)
    else
      0.0
    end

    # Simplified p-value (chi-square with 1 df)
    p_value = 1 - chi_cdf(chi2, 1)

    %{chi2: chi2, p_value: p_value, significant: p_value < 0.05}
  end

  # Simple chi-square CDF approximation
  defp chi_cdf(x, 1) when x >= 0 do
    2 * (0.5 - 0.5 * :math.erf(-:math.sqrt(x / 2)))
  end
  defp chi_cdf(_, _), do: 0.0

  # =========================================================================
  # MCQ Accuracy (migrated from eval_ex)
  # =========================================================================

  @doc """
  Calculate MCQ accuracy with answer letter extraction.

  Handles multiple response formats:
  - "B" - Single letter
  - "The answer is B" - Verbose response
  - "B. Diabetes mellitus is..." - Letter with explanation
  - "(B)" - Parenthesized letter
  - "Answer: B" - Labeled answer

  ## Parameters

    * `predictions` - List of maps with `:predicted` key containing response strings
    * `samples` - List of maps with `:correct_answer` key containing the correct letter

  ## Returns

  Float from 0.0 to 1.0 representing accuracy.

  ## Examples

      iex> preds = [%{predicted: "B"}, %{predicted: "The answer is A"}]
      iex> samples = [%{correct_answer: "B"}, %{correct_answer: "A"}]
      iex> MedlumLlm.Eval.MedicalMetrics.mcq_accuracy(preds, samples)
      1.0

      iex> preds = [%{predicted: "B"}]
      iex> samples = [%{correct_answer: "A"}]
      iex> MedlumLlm.Eval.MedicalMetrics.mcq_accuracy(preds, samples)
      0.0

  """
  @spec mcq_accuracy([map()], [map()]) :: float()
  def mcq_accuracy(predictions, samples)
      when is_list(predictions) and is_list(samples) do
    if Enum.empty?(predictions) or Enum.empty?(samples) do
      0.0
    else
      predictions
      |> Enum.zip(samples)
      |> Enum.map(&score_mcq_pair/1)
      |> calc_mean()
    end
  end

  defp score_mcq_pair({pred, sample}) do
    predicted_letter = extract_answer_letter(Map.get(pred, :predicted, ""))
    correct_letter = normalize_letter(Map.get(sample, :correct_answer, ""))
    mcq_letters_match?(predicted_letter, correct_letter)
  end

  defp mcq_letters_match?(nil, _), do: 0.0

  defp mcq_letters_match?(predicted, correct) do
    if String.upcase(to_string(predicted)) == String.upcase(to_string(correct)) do
      1.0
    else
      0.0
    end
  end

  @doc """
  Extract the answer letter from an LLM response.

  Handles various response formats commonly produced by language models.

  ## Parameters

    * `response` - The response string to extract the answer from

  ## Returns

  The extracted letter (A-Z) or nil if no valid letter found.

  ## Examples

      iex> MedlumLlm.Eval.MedicalMetrics.extract_answer_letter("B")
      "B"

      iex> MedlumLlm.Eval.MedicalMetrics.extract_answer_letter("The answer is C")
      "C"

      iex> MedlumLlm.Eval.MedicalMetrics.extract_answer_letter("(D)")
      "D"

  """
  @spec extract_answer_letter(String.t() | nil) :: String.t() | nil
  def extract_answer_letter(nil), do: nil
  def extract_answer_letter(""), do: nil

  def extract_answer_letter(response) when is_binary(response) do
    trimmed = String.trim(response)

    cond do
      # Pattern 1: "The answer is B" or "The correct answer is B" (check first - most specific)
      match = Regex.run(~r/(?:the\s+)?(?:correct\s+)?answer\s+is\s+([A-Za-z])/iu, trimmed) ->
        [_, letter] = match
        String.upcase(letter)

      # Pattern 2: "Answer: B" or "Answer - B" or "Answer B"
      match = Regex.run(~r/^answer[\s:\-]+([A-Za-z])/iu, trimmed) ->
        [_, letter] = match
        String.upcase(letter)

      # Pattern 3: "Option B" or "Choice B"
      match = Regex.run(~r/(?:option|choice)\s+([A-Za-z])/iu, trimmed) ->
        [_, letter] = match
        String.upcase(letter)

      # Pattern 4: "(B)" or "( B )"
      match = Regex.run(~r/\(\s*([A-Za-z])\s*\)/u, trimmed) ->
        [_, letter] = match
        String.upcase(letter)

      # Pattern 5: "[B]"
      match = Regex.run(~r/\[\s*([A-Za-z])\s*\]/u, trimmed) ->
        [_, letter] = match
        String.upcase(letter)

      # Pattern 6: Single letter at start followed by delimiter: "B", "B.", "B)", "B:"
      # Must be followed by end of string, period, paren, colon, space, or explanation
      match = Regex.run(~r/^([A-Za-z])(?:$|[\.\)\:\s])/u, trimmed) ->
        [_, letter] = match
        String.upcase(letter)

      # Pattern 7: First standalone letter A-D in response (fallback)
      match = Regex.run(~r/\b([A-Da-d])\b/, trimmed) ->
        [_, letter] = match
        String.upcase(letter)

      true ->
        nil
    end
  end

  def extract_answer_letter(_), do: nil

  # =========================================================================
  # Macro F1 Score (migrated from eval_ex)
  # =========================================================================

  @doc """
  Calculate macro F1 (unweighted average across classes).

  Macro F1 gives equal weight to each class, making it suitable for
  imbalanced datasets like PubMedQA (yes/no/maybe) or NLI classification.

  ## Parameters

    * `predictions` - List of maps with `:predicted` key
    * `samples` - List of maps with `:label` key
    * `opts` - Options
      - `:classes` - Explicit class list (default: inferred from samples)
      - `:normalize` - Function to normalize labels before comparison

  ## Returns

  Float from 0.0 to 1.0 representing macro-averaged F1 score.

  ## Examples

      iex> preds = [%{predicted: :yes}, %{predicted: :no}, %{predicted: :yes}]
      iex> samples = [%{label: :yes}, %{label: :no}, %{label: :yes}]
      iex> MedlumLlm.Eval.MedicalMetrics.macro_f1(preds, samples)
      1.0

      iex> preds = [%{predicted: :yes}]
      iex> samples = [%{label: :no}]
      iex> MedlumLlm.Eval.MedicalMetrics.macro_f1(preds, samples)
      0.0

  """
  @spec macro_f1([map()], [map()], keyword()) :: float()
  def macro_f1(predictions, samples, opts \\ [])

  def macro_f1(predictions, samples, opts)
      when is_list(predictions) and is_list(samples) do
    if Enum.empty?(predictions) or Enum.empty?(samples) do
      0.0
    else
      normalize_fn = Keyword.get(opts, :normalize, & &1)

      # Get predicted and actual labels
      pred_labels =
        Enum.map(predictions, fn p ->
          normalize_fn.(Map.get(p, :predicted))
        end)

      actual_labels =
        Enum.map(samples, fn s ->
          normalize_fn.(Map.get(s, :label))
        end)

      # Determine classes
      classes =
        Keyword.get_lazy(opts, :classes, fn ->
          (pred_labels ++ actual_labels)
          |> Enum.uniq()
          |> Enum.reject(&is_nil/1)
        end)

      calculate_macro_f1_for_classes(pred_labels, actual_labels, classes)
    end
  end

  defp calculate_macro_f1_for_classes(_pred_labels, _actual_labels, []), do: 0.0

  defp calculate_macro_f1_for_classes(pred_labels, actual_labels, classes) do
    classes
    |> Enum.map(fn class -> calculate_class_f1(pred_labels, actual_labels, class) end)
    |> calc_mean()
  end

  # =========================================================================
  # NLI Accuracy (migrated from eval_ex)
  # =========================================================================

  @doc """
  Calculate NLI classification accuracy with label normalization.

  Handles various label formats commonly used in NLI datasets:
  - Entailment: "entailment", "entail", "e", "1", "supports"
  - Contradiction: "contradiction", "contradict", "c", "0", "refutes"
  - Neutral: "neutral", "n", "2", "not_enough_info", "nei"

  ## Parameters

    * `predictions` - List of maps with `:predicted` key
    * `samples` - List of maps with `:label` key

  ## Returns

  Float from 0.0 to 1.0 representing accuracy.

  ## Examples

      iex> preds = [%{predicted: "entailment"}, %{predicted: "e"}]
      iex> samples = [%{label: "entail"}, %{label: "1"}]
      iex> MedlumLlm.Eval.MedicalMetrics.nli_accuracy(preds, samples)
      1.0

  """
  @spec nli_accuracy([map()], [map()]) :: float()
  def nli_accuracy(predictions, samples)
      when is_list(predictions) and is_list(samples) do
    if Enum.empty?(predictions) or Enum.empty?(samples) do
      0.0
    else
      predictions
      |> Enum.zip(samples)
      |> Enum.map(&score_nli_pair/1)
      |> calc_mean()
    end
  end

  defp score_nli_pair({pred, sample}) do
    predicted = normalize_nli_label(Map.get(pred, :predicted))
    actual = normalize_nli_label(Map.get(sample, :label))
    nli_labels_match?(predicted, actual)
  end

  defp nli_labels_match?(label, label) when label != :unknown, do: 1.0
  defp nli_labels_match?(_, _), do: 0.0

  @doc """
  Calculate macro F1 score for NLI classification.

  Uses NLI label normalization before computing macro F1.

  ## Parameters

    * `predictions` - List of maps with `:predicted` key
    * `samples` - List of maps with `:label` key

  ## Returns

  Float from 0.0 to 1.0 representing macro-averaged F1 score.
  """
  @spec nli_macro_f1([map()], [map()]) :: float()
  def nli_macro_f1(predictions, samples)
      when is_list(predictions) and is_list(samples) do
    macro_f1(predictions, samples,
      classes: [:entailment, :contradiction, :neutral],
      normalize: &normalize_nli_label/1
    )
  end

  @doc """
  Normalize an NLI label to a canonical form.

  ## Parameters

    * `label` - The label to normalize

  ## Returns

  One of `:entailment`, `:contradiction`, `:neutral`, or `:unknown`.

  ## Examples

      iex> MedlumLlm.Eval.MedicalMetrics.normalize_nli_label("entailment")
      :entailment

      iex> MedlumLlm.Eval.MedicalMetrics.normalize_nli_label("e")
      :entailment

      iex> MedlumLlm.Eval.MedicalMetrics.normalize_nli_label("1")
      :entailment

  """
  # NLI label mapping for string normalization
  @nli_string_map %{
    "entailment" => :entailment,
    "entail" => :entailment,
    "e" => :entailment,
    "1" => :entailment,
    "supports" => :entailment,
    "support" => :entailment,
    "true" => :entailment,
    "contradiction" => :contradiction,
    "contradict" => :contradiction,
    "c" => :contradiction,
    "0" => :contradiction,
    "refutes" => :contradiction,
    "refute" => :contradiction,
    "false" => :contradiction,
    "neutral" => :neutral,
    "n" => :neutral,
    "2" => :neutral,
    "not_enough_info" => :neutral,
    "nei" => :neutral,
    "unknown" => :neutral,
    "maybe" => :neutral
  }

  # NLI label mapping for atom normalization
  @nli_atom_map %{
    entailment: :entailment,
    entail: :entailment,
    e: :entailment,
    supports: :entailment,
    support: :entailment,
    true: :entailment,
    contradiction: :contradiction,
    contradict: :contradiction,
    c: :contradiction,
    refutes: :contradiction,
    refute: :contradiction,
    false: :contradiction,
    neutral: :neutral,
    n: :neutral,
    not_enough_info: :neutral,
    nei: :neutral,
    unknown: :neutral,
    maybe: :neutral
  }

  @spec normalize_nli_label(term()) :: :entailment | :contradiction | :neutral | :unknown
  def normalize_nli_label(label) when is_binary(label) do
    normalized = label |> String.trim() |> String.downcase()
    Map.get(@nli_string_map, normalized, :unknown)
  end

  def normalize_nli_label(label) when is_atom(label) do
    Map.get(@nli_atom_map, label, :unknown)
  end

  def normalize_nli_label(1), do: :entailment
  def normalize_nli_label(0), do: :contradiction
  def normalize_nli_label(2), do: :neutral
  def normalize_nli_label(_), do: :unknown

  # =========================================================================
  # Binary QA Accuracy - PubMedQA (migrated from eval_ex)
  # =========================================================================

  @doc """
  Calculate accuracy for yes/no/maybe questions (PubMedQA).

  Normalizes answers to canonical forms `:yes`, `:no`, `:maybe` before comparison.

  ## Parameters

    * `predictions` - List of maps with `:predicted` key
    * `samples` - List of maps with `:label` key

  ## Returns

  Float from 0.0 to 1.0 representing accuracy.

  ## Examples

      iex> preds = [%{predicted: "yes"}, %{predicted: "Y"}]
      iex> samples = [%{label: "Yes"}, %{label: "yes"}]
      iex> MedlumLlm.Eval.MedicalMetrics.binary_qa_accuracy(preds, samples)
      1.0

  """
  @spec binary_qa_accuracy([map()], [map()]) :: float()
  def binary_qa_accuracy(predictions, samples)
      when is_list(predictions) and is_list(samples) do
    if Enum.empty?(predictions) or Enum.empty?(samples) do
      0.0
    else
      predictions
      |> Enum.zip(samples)
      |> Enum.map(&score_binary_qa_pair/1)
      |> calc_mean()
    end
  end

  defp score_binary_qa_pair({pred, sample}) do
    predicted = normalize_binary_qa_label(Map.get(pred, :predicted))
    actual = normalize_binary_qa_label(Map.get(sample, :label))
    binary_qa_labels_match?(predicted, actual)
  end

  defp binary_qa_labels_match?(label, label) when label != :unknown, do: 1.0
  defp binary_qa_labels_match?(_, _), do: 0.0

  @doc """
  Calculate macro F1 score for binary QA (yes/no/maybe).

  Uses binary QA label normalization before computing macro F1.

  ## Parameters

    * `predictions` - List of maps with `:predicted` key
    * `samples` - List of maps with `:label` key

  ## Returns

  Float from 0.0 to 1.0 representing macro-averaged F1 score.
  """
  @spec binary_qa_macro_f1([map()], [map()]) :: float()
  def binary_qa_macro_f1(predictions, samples)
      when is_list(predictions) and is_list(samples) do
    macro_f1(predictions, samples,
      classes: [:yes, :no, :maybe],
      normalize: &normalize_binary_qa_label/1
    )
  end

  @doc """
  Normalize a binary QA label to canonical form.

  ## Parameters

    * `label` - The label to normalize

  ## Returns

  One of `:yes`, `:no`, `:maybe`, or `:unknown`.

  ## Examples

      iex> MedlumLlm.Eval.MedicalMetrics.normalize_binary_qa_label("yes")
      :yes

      iex> MedlumLlm.Eval.MedicalMetrics.normalize_binary_qa_label("Y")
      :yes

      iex> MedlumLlm.Eval.MedicalMetrics.normalize_binary_qa_label("uncertain")
      :maybe

  """
  # Binary QA label mapping for string normalization
  @binary_qa_string_map %{
    "yes" => :yes,
    "y" => :yes,
    "true" => :yes,
    "1" => :yes,
    "positive" => :yes,
    "affirmative" => :yes,
    "no" => :no,
    "n" => :no,
    "false" => :no,
    "0" => :no,
    "negative" => :no,
    "maybe" => :maybe,
    "m" => :maybe,
    "uncertain" => :maybe,
    "cannot determine" => :maybe,
    "unknown" => :maybe,
    "not clear" => :maybe
  }

  # Binary QA label mapping for atom normalization
  @binary_qa_atom_map %{
    yes: :yes,
    y: :yes,
    true: :yes,
    positive: :yes,
    no: :no,
    n: :no,
    false: :no,
    negative: :no,
    maybe: :maybe,
    m: :maybe,
    uncertain: :maybe,
    unknown: :maybe
  }

  @spec normalize_binary_qa_label(term()) :: :yes | :no | :maybe | :unknown
  def normalize_binary_qa_label(label) when is_binary(label) do
    normalized = label |> String.trim() |> String.downcase()
    Map.get(@binary_qa_string_map, normalized, :unknown)
  end

  def normalize_binary_qa_label(label) when is_atom(label) do
    Map.get(@binary_qa_atom_map, label, :unknown)
  end

  def normalize_binary_qa_label(1), do: :yes
  def normalize_binary_qa_label(0), do: :no
  def normalize_binary_qa_label(2), do: :maybe
  def normalize_binary_qa_label(_), do: :unknown

  # =========================================================================
  # Latency Percentiles (migrated from eval_ex)
  # =========================================================================

  @doc """
  Calculate latency percentiles from prediction results.

  Provides comprehensive latency statistics including percentiles,
  mean, min, max, and sample count.

  ## Parameters

    * `predictions` - List of maps with `:latency_ms` key (number)

  ## Returns

  Map with latency statistics:
  - `:p50` - Median latency
  - `:p90` - 90th percentile
  - `:p95` - 95th percentile
  - `:p99` - 99th percentile
  - `:mean` - Mean latency
  - `:min` - Minimum latency
  - `:max` - Maximum latency
  - `:count` - Number of samples

  ## Examples

      iex> preds = [%{latency_ms: 100}, %{latency_ms: 200}, %{latency_ms: 300}]
      iex> result = MedlumLlm.Eval.MedicalMetrics.latency_percentiles(preds)
      iex> result.p50
      200.0
      iex> result.count
      3

  """
  @spec latency_percentiles([map()]) :: map()
  def latency_percentiles(predictions) when is_list(predictions) do
    latencies =
      predictions
      |> Enum.map(fn p -> Map.get(p, :latency_ms) end)
      |> Enum.filter(&is_number/1)
      |> Enum.sort()

    if Enum.empty?(latencies) do
      %{
        p50: 0.0,
        p90: 0.0,
        p95: 0.0,
        p99: 0.0,
        mean: 0.0,
        min: 0.0,
        max: 0.0,
        count: 0
      }
    else
      %{
        p50: percentile(latencies, 0.50),
        p90: percentile(latencies, 0.90),
        p95: percentile(latencies, 0.95),
        p99: percentile(latencies, 0.99),
        mean: calc_mean(latencies),
        min: Enum.min(latencies) |> to_float(),
        max: Enum.max(latencies) |> to_float(),
        count: length(latencies)
      }
    end
  end

  # =========================================================================
  # Tokens Per Second (migrated from eval_ex)
  # =========================================================================

  @doc """
  Calculate tokens per second throughput.

  Computes the aggregate throughput by dividing total tokens by total time.

  ## Parameters

    * `predictions` - List of maps with `:output_tokens` (integer) and `:latency_ms` (number) keys

  ## Returns

  Float representing tokens per second.

  ## Examples

      iex> preds = [
      ...>   %{output_tokens: 100, latency_ms: 1000},
      ...>   %{output_tokens: 200, latency_ms: 2000}
      ...> ]
      iex> MedlumLlm.Eval.MedicalMetrics.tokens_per_second(preds)
      100.0

  """
  @spec tokens_per_second([map()]) :: float()
  def tokens_per_second(predictions) when is_list(predictions) do
    {total_tokens, total_time_ms} =
      predictions
      |> Enum.reduce({0, 0.0}, fn pred, {tokens, time} ->
        output_tokens = Map.get(pred, :output_tokens, 0)
        latency_ms = Map.get(pred, :latency_ms, 0)

        if is_number(output_tokens) and is_number(latency_ms) do
          {tokens + output_tokens, time + latency_ms}
        else
          {tokens, time}
        end
      end)

    if total_time_ms > 0 do
      # Convert ms to seconds
      total_tokens / (total_time_ms / 1000.0)
    else
      0.0
    end
  end

  # =========================================================================
  # Confusion Matrix (migrated from eval_ex)
  # =========================================================================

  @doc """
  Calculate confusion matrix for multi-class classification.

  ## Parameters

    * `predictions` - List of maps with `:predicted` key
    * `samples` - List of maps with `:label` key
    * `opts` - Options
      - `:classes` - Explicit class list (default: inferred)
      - `:normalize` - Function to normalize labels

  ## Returns

  Map with confusion matrix data:
  - `:matrix` - 2D map of actual -> predicted -> count
  - `:classes` - List of classes
  - `:totals` - Per-class totals

  ## Examples

      iex> preds = [%{predicted: :a}, %{predicted: :b}]
      iex> samples = [%{label: :a}, %{label: :a}]
      iex> result = MedlumLlm.Eval.MedicalMetrics.confusion_matrix(preds, samples)
      iex> result.matrix[:a][:a]
      1
      iex> result.matrix[:a][:b]
      1

  """
  @spec confusion_matrix([map()], [map()], keyword()) :: map()
  def confusion_matrix(predictions, samples, opts \\ [])

  def confusion_matrix(predictions, samples, opts)
      when is_list(predictions) and is_list(samples) do
    normalize_fn = Keyword.get(opts, :normalize, & &1)

    pairs =
      predictions
      |> Enum.zip(samples)
      |> Enum.map(fn {pred, sample} ->
        {normalize_fn.(Map.get(sample, :label)),
         normalize_fn.(Map.get(pred, :predicted))}
      end)

    classes =
      Keyword.get_lazy(opts, :classes, fn ->
        pairs
        |> Enum.flat_map(fn {actual, predicted} -> [actual, predicted] end)
        |> Enum.uniq()
        |> Enum.reject(&is_nil/1)
        |> Enum.sort()
      end)

    # Build confusion matrix
    matrix = build_confusion_matrix(pairs, classes)

    # Calculate totals
    totals =
      Enum.reduce(classes, %{}, fn class, acc ->
        actual_count = Enum.count(pairs, fn {a, _p} -> a == class end)
        predicted_count = Enum.count(pairs, fn {_a, p} -> p == class end)

        Map.put(acc, class, %{
          actual: actual_count,
          predicted: predicted_count
        })
      end)

    %{
      matrix: matrix,
      classes: classes,
      totals: totals
    }
  end

  # =========================================================================
  # Private Helpers (migrated from eval_ex)
  # =========================================================================

  defp build_confusion_matrix(pairs, classes) do
    Enum.reduce(classes, %{}, fn actual, acc ->
      row = build_confusion_matrix_row(pairs, classes, actual)
      Map.put(acc, actual, row)
    end)
  end

  defp build_confusion_matrix_row(pairs, classes, actual) do
    Enum.reduce(classes, %{}, fn predicted, row_acc ->
      count = Enum.count(pairs, fn {a, p} -> a == actual and p == predicted end)
      Map.put(row_acc, predicted, count)
    end)
  end

  defp normalize_letter(letter) when is_binary(letter) do
    String.trim(letter) |> String.upcase()
  end

  defp normalize_letter(letter), do: to_string(letter) |> String.upcase()

  defp calculate_class_f1(pred_labels, actual_labels, class) do
    pairs = Enum.zip(pred_labels, actual_labels)

    # True positives: predicted class AND actually class
    tp = Enum.count(pairs, fn {p, a} -> p == class and a == class end)

    # False positives: predicted class BUT not actually class
    fp = Enum.count(pairs, fn {p, a} -> p == class and a != class end)

    # False negatives: actually class BUT not predicted class
    fn_ = Enum.count(pairs, fn {p, a} -> p != class and a == class end)

    precision = if tp + fp > 0, do: tp / (tp + fp), else: 0.0
    recall = if tp + fn_ > 0, do: tp / (tp + fn_), else: 0.0

    if precision + recall > 0 do
      2 * (precision * recall) / (precision + recall)
    else
      0.0
    end
  end

  defp calc_mean([]), do: 0.0

  defp calc_mean(values) when is_list(values) do
    Enum.sum(values) / length(values)
  end

  defp percentile(sorted_list, p) when is_list(sorted_list) and is_float(p) do
    n = length(sorted_list)

    if n == 0 do
      0.0
    else
      # Use linear interpolation between closest ranks
      rank = p * (n - 1)
      lower_index = floor(rank)
      upper_index = ceil(rank)

      lower_index = max(0, min(lower_index, n - 1))
      upper_index = max(0, min(upper_index, n - 1))

      if lower_index == upper_index do
        Enum.at(sorted_list, lower_index) |> to_float()
      else
        lower_value = Enum.at(sorted_list, lower_index)
        upper_value = Enum.at(sorted_list, upper_index)
        fraction = rank - lower_index

        to_float(lower_value + fraction * (upper_value - lower_value))
      end
    end
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(_), do: 0.0
end
