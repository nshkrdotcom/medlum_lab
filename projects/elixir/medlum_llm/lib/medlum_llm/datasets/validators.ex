defmodule MedlumLlm.Datasets.Validators do
  @moduledoc """
  Format validators for medical datasets.

  Provides validation functions for different medical dataset formats:
  - MCQ (Multiple Choice Questions)
  - Binary QA (Yes/No/Maybe)
  - NER (Named Entity Recognition)
  - CVL (Clinical Verification Layer training data)
  - Reasoning (Chain-of-thought medical reasoning)

  Each validator checks:
  - Required fields are present
  - Field types are correct
  - Field values are in valid ranges
  - Format-specific constraints are met

  ## Examples

      # Validate MCQ dataset
      {:ok, report} = Validators.validate_mcq(dataset)

      # Validate with custom checks
      {:ok, report} = Validators.validate_mcq(dataset,
        custom_checks: [&my_custom_check/1]
      )

      # Full quality check combining multiple validators
      {:ok, report} = Validators.full_quality_check(dataset, :mcq)
  """

  alias DatasetsEx.{Dataset, Quality}

  @type validation_report :: %{
          valid: boolean(),
          total_items: non_neg_integer(),
          valid_items: non_neg_integer(),
          invalid_items: non_neg_integer(),
          errors: [String.t()],
          warnings: [String.t()]
        }

  @doc """
  Validate MCQ format dataset.

  Required keys: `:question`, `:options`, `:correct_answer`
  - Options must be a list of 4 strings
  - Answer must be A/B/C/D

  ## Options
    - `:custom_checks` - List of additional check functions
    - `:allow_missing_explanation` - Allow missing explanation field (default: true)

  ## Examples

      {:ok, report} = Validators.validate_mcq(dataset)
      # => %{valid: true, total_items: 100, valid_items: 100, ...}
  """
  @spec validate_mcq(Dataset.t(), keyword()) :: {:ok, validation_report()} | {:error, term()}
  def validate_mcq(%Dataset{} = dataset, opts \\ []) do
    custom_checks = Keyword.get(opts, :custom_checks, [])

    checks = [
      &check_mcq_required_fields/1,
      &check_mcq_options/1,
      &check_mcq_answer/1,
      &check_no_duplicate_options/1
    ] ++ custom_checks

    validate_format(dataset, checks, opts)
  end

  @doc """
  Validate binary QA format dataset (PubMedQA style).

  Required keys: `:question`, `:context`, `:answer`
  - Answer must be "yes", "no", or "maybe"

  ## Options
    - `:custom_checks` - List of additional check functions
    - `:require_explanation` - Require explanation field (default: false)

  ## Examples

      {:ok, report} = Validators.validate_binary_qa(dataset)
  """
  @spec validate_binary_qa(Dataset.t(), keyword()) :: {:ok, validation_report()} | {:error, term()}
  def validate_binary_qa(%Dataset{} = dataset, opts \\ []) do
    custom_checks = Keyword.get(opts, :custom_checks, [])
    require_explanation = Keyword.get(opts, :require_explanation, false)

    checks = [
      &check_binary_qa_required_fields/1,
      &check_binary_qa_answer/1,
      &check_context_not_empty/1
    ]

    checks =
      if require_explanation do
        checks ++ [&check_explanation_present/1]
      else
        checks
      end

    checks = checks ++ custom_checks

    validate_format(dataset, checks, opts)
  end

  @doc """
  Validate NER format dataset.

  Required keys: `:text`, `:entities`
  - Entities must be a list with valid span information
  - Entity spans must be within text bounds
  - No overlapping entity spans

  ## Options
    - `:custom_checks` - List of additional check functions
    - `:allow_overlapping` - Allow overlapping entities (default: false)

  ## Examples

      {:ok, report} = Validators.validate_ner(dataset)
  """
  @spec validate_ner(Dataset.t(), keyword()) :: {:ok, validation_report()} | {:error, term()}
  def validate_ner(%Dataset{} = dataset, opts \\ []) do
    custom_checks = Keyword.get(opts, :custom_checks, [])
    allow_overlapping = Keyword.get(opts, :allow_overlapping, false)

    checks = [
      &check_ner_required_fields/1,
      &check_entity_spans_valid/1,
      &check_entity_spans_in_bounds/1
    ]

    checks =
      if not allow_overlapping do
        checks ++ [&check_no_overlapping_entities/1]
      else
        checks
      end

    checks = checks ++ custom_checks

    validate_format(dataset, checks, opts)
  end

  @doc """
  Validate CVL training format dataset.

  Required keys: `:premise`, `:hypothesis`, `:verdict`
  - Verdict must be `:entailment`, `:contradiction`, or `:neutral`

  ## Options
    - `:custom_checks` - List of additional check functions
    - `:require_evidence` - Require evidence field (default: false)

  ## Examples

      {:ok, report} = Validators.validate_cvl(dataset)
  """
  @spec validate_cvl(Dataset.t(), keyword()) :: {:ok, validation_report()} | {:error, term()}
  def validate_cvl(%Dataset{} = dataset, opts \\ []) do
    custom_checks = Keyword.get(opts, :custom_checks, [])
    require_evidence = Keyword.get(opts, :require_evidence, false)

    checks = [
      &check_cvl_required_fields/1,
      &check_cvl_verdict/1,
      &check_premise_hypothesis_not_empty/1
    ]

    checks =
      if require_evidence do
        checks ++ [&check_evidence_present/1]
      else
        checks
      end

    checks = checks ++ custom_checks

    validate_format(dataset, checks, opts)
  end

  @doc """
  Validate reasoning format dataset.

  Required keys: `:question`, `:thinking`, `:answer`

  ## Options
    - `:custom_checks` - List of additional check functions
    - `:min_thinking_length` - Minimum thinking text length (default: 50)

  ## Examples

      {:ok, report} = Validators.validate_reasoning(dataset)
  """
  @spec validate_reasoning(Dataset.t(), keyword()) :: {:ok, validation_report()} | {:error, term()}
  def validate_reasoning(%Dataset{} = dataset, opts \\ []) do
    custom_checks = Keyword.get(opts, :custom_checks, [])
    min_thinking_length = Keyword.get(opts, :min_thinking_length, 50)

    checks = [
      &check_reasoning_required_fields/1,
      fn item -> check_thinking_length(item, min_thinking_length) end
    ] ++ custom_checks

    validate_format(dataset, checks, opts)
  end

  @doc """
  Run full quality check combining format validation with profiling.

  Combines format-specific validation with:
  - Schema validation
  - Duplicate detection
  - Label distribution analysis
  - Dataset profiling

  ## Parameters
    - `dataset` - Dataset to validate
    - `format` - Format type (`:mcq`, `:binary_qa`, `:ner`, `:cvl`, `:reasoning`)

  ## Options
    - All options supported by format-specific validators
    - `:profile_opts` - Options for profiling

  ## Returns

  Comprehensive report with:
    - Format validation results
    - Duplicate analysis
    - Label/verdict distribution
    - Text statistics

  ## Examples

      {:ok, report} = Validators.full_quality_check(dataset, :mcq)
      report.format_validation
      # => %{valid: true, total_items: 100, ...}
      report.duplicates
      # => %{duplicate_rate: 0.02, ...}
  """
  @spec full_quality_check(Dataset.t(), atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def full_quality_check(%Dataset{} = dataset, format, opts \\ []) do
    with {:ok, format_report} <- validate_by_format(dataset, format, opts) do
      # Run additional quality checks
      duplicate_report =
        Quality.detect_duplicates(dataset, key: primary_key_for_format(format))

      distribution_report =
        Quality.label_distribution(dataset, label_key: label_key_for_format(format))

      profile_report =
        Quality.profile(dataset,
          text_key: text_key_for_format(format),
          compute_vocab: Keyword.get(opts, :compute_vocab, true)
        )

      {:ok,
       %{
         format: format,
         format_validation: format_report,
         duplicates: duplicate_report,
         distribution: distribution_report,
         profile: profile_report,
         overall_valid: format_report.valid and duplicate_report.duplicate_rate < 0.1,
         checked_at: DateTime.utc_now()
       }}
    end
  end

  @doc """
  Check if an answer is in the question (potential data leakage).

  Useful as a custom check to detect questions where the answer
  appears verbatim in the question text.

  ## Examples

      # Use as custom check
      Validators.validate_mcq(dataset, custom_checks: [&Validators.check_answer_not_in_question/1])
  """
  @spec check_answer_not_in_question(map()) :: :ok | {:error, String.t()}
  def check_answer_not_in_question(item) do
    question = Map.get(item, :question, "") |> String.downcase()
    correct_answer = Map.get(item, :correct_answer, "")

    options = Map.get(item, :options, [])
    answer_idx = answer_to_index(correct_answer)
    answer_text = Enum.at(options, answer_idx, "") |> String.downcase()

    if answer_text != "" and String.contains?(question, answer_text) do
      {:error, "Answer text appears in question (potential leakage)"}
    else
      :ok
    end
  end

  # Private implementation

  defp validate_format(dataset, checks, _opts) do
    data = get_all_data(dataset)
    total = length(data)

    {valid_items, errors} =
      data
      |> Enum.with_index()
      |> Enum.reduce({0, []}, fn {item, idx}, {valid_count, error_list} ->
        item_errors =
          Enum.reduce(checks, [], fn check, acc ->
            case check.(item) do
              :ok -> acc
              {:error, msg} -> ["Item #{idx}: #{msg}" | acc]
            end
          end)

        if Enum.empty?(item_errors) do
          {valid_count + 1, error_list}
        else
          {valid_count, error_list ++ item_errors}
        end
      end)

    report = %{
      valid: Enum.empty?(errors),
      total_items: total,
      valid_items: valid_items,
      invalid_items: total - valid_items,
      errors: Enum.take(errors, 100),
      warnings: []
    }

    {:ok, report}
  end

  defp validate_by_format(dataset, :mcq, opts), do: validate_mcq(dataset, opts)
  defp validate_by_format(dataset, :binary_qa, opts), do: validate_binary_qa(dataset, opts)
  defp validate_by_format(dataset, :ner, opts), do: validate_ner(dataset, opts)
  defp validate_by_format(dataset, :cvl, opts), do: validate_cvl(dataset, opts)
  defp validate_by_format(dataset, :reasoning, opts), do: validate_reasoning(dataset, opts)
  defp validate_by_format(_dataset, format, _opts), do: {:error, {:unknown_format, format}}

  # MCQ Checks

  defp check_mcq_required_fields(item) do
    required = [:question, :options, :correct_answer]
    check_required_fields(item, required)
  end

  defp check_mcq_options(item) do
    options = Map.get(item, :options)

    cond do
      not is_list(options) ->
        {:error, "options must be a list"}

      length(options) != 4 ->
        {:error, "options must have exactly 4 items, got #{length(options)}"}

      not Enum.all?(options, &is_binary/1) ->
        {:error, "all options must be strings"}

      Enum.any?(options, fn o -> String.trim(o) == "" end) ->
        {:error, "options cannot be empty strings"}

      true ->
        :ok
    end
  end

  defp check_mcq_answer(item) do
    answer = Map.get(item, :correct_answer)

    cond do
      answer in ["A", "B", "C", "D"] -> :ok
      answer in [0, 1, 2, 3] -> :ok
      true -> {:error, "correct_answer must be A/B/C/D or 0-3, got #{inspect(answer)}"}
    end
  end

  defp check_no_duplicate_options(item) do
    options = Map.get(item, :options, [])
    unique_options = Enum.uniq(options)

    if length(unique_options) == length(options) do
      :ok
    else
      {:error, "options contain duplicates"}
    end
  end

  # Binary QA Checks

  defp check_binary_qa_required_fields(item) do
    required = [:question, :context, :answer]
    check_required_fields(item, required)
  end

  defp check_binary_qa_answer(item) do
    answer = Map.get(item, :answer)
    answer_lower = if is_binary(answer), do: String.downcase(answer), else: answer

    if answer_lower in ["yes", "no", "maybe"] do
      :ok
    else
      {:error, "answer must be yes/no/maybe, got #{inspect(answer)}"}
    end
  end

  defp check_context_not_empty(item) do
    context = Map.get(item, :context, "")

    if is_binary(context) and String.trim(context) != "" do
      :ok
    else
      {:error, "context cannot be empty"}
    end
  end

  defp check_explanation_present(item) do
    explanation = Map.get(item, :explanation)

    if is_binary(explanation) and String.trim(explanation) != "" do
      :ok
    else
      {:error, "explanation is required but missing or empty"}
    end
  end

  # NER Checks

  defp check_ner_required_fields(item) do
    required = [:text, :entities]
    check_required_fields(item, required)
  end

  defp check_entity_spans_valid(item) do
    entities = Map.get(item, :entities, [])

    if is_list(entities) do
      invalid =
        Enum.with_index(entities)
        |> Enum.reject(fn {entity, _idx} ->
          start_pos = Map.get(entity, :start, Map.get(entity, "start"))
          end_pos = Map.get(entity, :end_pos, Map.get(entity, :end, Map.get(entity, "end")))

          is_integer(start_pos) and is_integer(end_pos) and start_pos >= 0 and end_pos > start_pos
        end)

      if Enum.empty?(invalid) do
        :ok
      else
        {:error, "#{length(invalid)} entities have invalid spans"}
      end
    else
      {:error, "entities must be a list"}
    end
  end

  defp check_entity_spans_in_bounds(item) do
    text = Map.get(item, :text, "")
    text_length = String.length(text)
    entities = Map.get(item, :entities, [])

    out_of_bounds =
      Enum.filter(entities, fn entity ->
        end_pos = Map.get(entity, :end_pos, Map.get(entity, :end, Map.get(entity, "end", 0)))
        end_pos > text_length
      end)

    if Enum.empty?(out_of_bounds) do
      :ok
    else
      {:error, "#{length(out_of_bounds)} entity spans exceed text length"}
    end
  end

  defp check_no_overlapping_entities(item) do
    entities = Map.get(item, :entities, [])

    spans =
      Enum.map(entities, fn entity ->
        start_pos = Map.get(entity, :start, Map.get(entity, "start", 0))
        end_pos = Map.get(entity, :end_pos, Map.get(entity, :end, Map.get(entity, "end", 0)))
        {start_pos, end_pos}
      end)
      |> Enum.sort()

    has_overlap =
      spans
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.any?(fn [{_s1, e1}, {s2, _e2}] -> s2 < e1 end)

    if has_overlap do
      {:error, "entities have overlapping spans"}
    else
      :ok
    end
  end

  # CVL Checks

  defp check_cvl_required_fields(item) do
    required = [:premise, :hypothesis, :verdict]
    check_required_fields(item, required)
  end

  defp check_cvl_verdict(item) do
    verdict = Map.get(item, :verdict)

    if verdict in [:entailment, :contradiction, :neutral] do
      :ok
    else
      {:error, "verdict must be :entailment/:contradiction/:neutral, got #{inspect(verdict)}"}
    end
  end

  defp check_premise_hypothesis_not_empty(item) do
    premise = Map.get(item, :premise, "")
    hypothesis = Map.get(item, :hypothesis, "")

    cond do
      not is_binary(premise) or String.trim(premise) == "" ->
        {:error, "premise cannot be empty"}

      not is_binary(hypothesis) or String.trim(hypothesis) == "" ->
        {:error, "hypothesis cannot be empty"}

      true ->
        :ok
    end
  end

  defp check_evidence_present(item) do
    evidence = Map.get(item, :evidence)

    if is_list(evidence) and length(evidence) > 0 do
      :ok
    else
      {:error, "evidence is required but missing or empty"}
    end
  end

  # Reasoning Checks

  defp check_reasoning_required_fields(item) do
    required = [:question, :thinking, :answer]
    check_required_fields(item, required)
  end

  defp check_thinking_length(item, min_length) do
    thinking = Map.get(item, :thinking, "")

    if is_binary(thinking) and String.length(thinking) >= min_length do
      :ok
    else
      {:error, "thinking must be at least #{min_length} characters"}
    end
  end

  # Helper functions

  defp check_required_fields(item, required) do
    missing = Enum.reject(required, &Map.has_key?(item, &1))

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "missing required fields: #{inspect(missing)}"}
    end
  end

  defp get_all_data(%Dataset{data: data}) when is_list(data), do: data

  defp get_all_data(%Dataset{splits: splits}) when map_size(splits) > 0 do
    splits |> Map.values() |> List.flatten()
  end

  defp get_all_data(_), do: []

  defp primary_key_for_format(:mcq), do: :question
  defp primary_key_for_format(:binary_qa), do: :question
  defp primary_key_for_format(:ner), do: :text
  defp primary_key_for_format(:cvl), do: :premise
  defp primary_key_for_format(:reasoning), do: :question
  defp primary_key_for_format(_), do: :id

  defp label_key_for_format(:mcq), do: :correct_answer
  defp label_key_for_format(:binary_qa), do: :answer
  defp label_key_for_format(:ner), do: :entities
  defp label_key_for_format(:cvl), do: :verdict
  defp label_key_for_format(:reasoning), do: :subject
  defp label_key_for_format(_), do: :label

  defp text_key_for_format(:mcq), do: :question
  defp text_key_for_format(:binary_qa), do: :context
  defp text_key_for_format(:ner), do: :text
  defp text_key_for_format(:cvl), do: :premise
  defp text_key_for_format(:reasoning), do: :thinking
  defp text_key_for_format(_), do: :text

  defp answer_to_index("A"), do: 0
  defp answer_to_index("B"), do: 1
  defp answer_to_index("C"), do: 2
  defp answer_to_index("D"), do: 3
  defp answer_to_index(n) when is_integer(n) and n in 0..3, do: n
  defp answer_to_index(_), do: 0
end
