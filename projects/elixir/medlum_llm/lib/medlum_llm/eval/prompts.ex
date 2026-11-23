defmodule MedlumLlm.Eval.Prompts do
  @moduledoc """
  Prompt templates for medical evaluation.

  Formats samples into prompts and parses model responses.

  ## Available Templates

  - `:zero_shot_mcq` - Direct MCQ without examples
  - `:few_shot_mcq` - MCQ with training examples
  - `:chain_of_thought_mcq` - MCQ with step-by-step reasoning
  - `:zero_shot_binary_qa` - Yes/No/Maybe questions
  - `:reasoning_eval` - Open-ended reasoning problems

  ## Usage

      # Format a sample into a prompt
      sample = %{question: "What is...", options: ["A. ...", "B. ..."]}
      prompt = MedlumLlm.Eval.Prompts.format(:zero_shot_mcq, sample)

      # Parse model response
      answer = MedlumLlm.Eval.Prompts.parse_mcq_response("The answer is B")
      #=> "B"
  """

  @templates %{
    zero_shot_mcq: """
    Answer the following medical question by selecting the correct option (A, B, C, or D).

    Question: <%= @question %>

    <%= Enum.join(@options, "\\n") %>

    Answer with only the letter (A, B, C, or D):
    """,

    few_shot_mcq: """
    Answer medical questions by selecting the correct option.

    <%= for ex <- @examples do %>
    Question: <%= ex.question %>
    <%= Enum.join(ex.options, "\\n") %>
    Answer: <%= ex.answer %>

    <% end %>
    Question: <%= @question %>
    <%= Enum.join(@options, "\\n") %>
    Answer:
    """,

    chain_of_thought_mcq: """
    Answer the following medical question. First, reason through the problem step by step, then provide your final answer.

    Question: <%= @question %>

    <%= Enum.join(@options, "\\n") %>

    Let's think through this step by step:
    """,

    zero_shot_binary_qa: """
    Based on the following context from a PubMed abstract, answer the question with "yes", "no", or "maybe".

    Context: <%= @context %>

    Question: <%= @question %>

    Answer (yes/no/maybe):
    """,

    reasoning_eval: """
    Solve the following medical problem, showing your reasoning.

    Problem: <%= @question %>

    Solution:
    """
  }

  @doc """
  Format a sample into a prompt using a template.

  ## Examples

      sample = %{
        question: "What are the symptoms of MI?",
        options: ["A. Chest pain", "B. Headache", "C. Leg pain", "D. Back pain"]
      }

      prompt = MedlumLlm.Eval.Prompts.format(:zero_shot_mcq, sample)
      # => "Answer the following medical question...\\n\\nQuestion: What are..."

  """
  @spec format(atom(), map()) :: String.t()
  def format(template_name, sample) do
    template = Map.fetch!(@templates, template_name)
    assigns = sample_to_assigns(sample)
    EEx.eval_string(template, assigns: assigns)
  end

  @doc """
  Get raw template string for inspection.

  ## Examples

      template = MedlumLlm.Eval.Prompts.get_template(:zero_shot_mcq)

  """
  @spec get_template(atom()) :: String.t() | nil
  def get_template(name), do: Map.get(@templates, name)

  @doc """
  List available template names.

  ## Examples

      MedlumLlm.Eval.Prompts.list_templates()
      #=> [:zero_shot_mcq, :few_shot_mcq, :chain_of_thought_mcq, ...]

  """
  @spec list_templates() :: [atom()]
  def list_templates, do: Map.keys(@templates)

  @doc """
  Parse MCQ response to extract answer letter.

  Handles various response formats:
  - Direct letter: "A"
  - "Answer: A"
  - "The answer is A"
  - "(A)" in parentheses
  - Letter at start: "A. Because..."

  ## Examples

      MedlumLlm.Eval.Prompts.parse_mcq_response("A")
      #=> "A"

      MedlumLlm.Eval.Prompts.parse_mcq_response("The answer is B")
      #=> "B"

      MedlumLlm.Eval.Prompts.parse_mcq_response("(C)")
      #=> "C"

      MedlumLlm.Eval.Prompts.parse_mcq_response("I don't know")
      #=> nil

  """
  @spec parse_mcq_response(String.t()) :: String.t() | nil
  def parse_mcq_response(response) do
    response = String.trim(response)

    cond do
      # Direct letter
      response in ~w(A B C D a b c d) ->
        String.upcase(response)

      # "Answer: A" or "The answer is A" or "correct: B"
      Regex.match?(~r/(?:answer|correct)(?:\s+is)?[:\s]+([A-Da-d])\b/i, response) ->
        case Regex.run(~r/(?:answer|correct)(?:\s+is)?[:\s]+([A-Da-d])\b/i, response) do
          [_, letter] -> String.upcase(letter)
          _ -> nil
        end

      # First letter in parentheses: "(A)"
      Regex.match?(~r/\(([A-Da-d])\)/, response) ->
        case Regex.run(~r/\(([A-Da-d])\)/, response) do
          [_, letter] -> String.upcase(letter)
          _ -> nil
        end

      # First standalone letter at start of response
      Regex.match?(~r/^([A-Da-d])\b/, response) ->
        case Regex.run(~r/^([A-Da-d])\b/, response) do
          [_, letter] -> String.upcase(letter)
          _ -> nil
        end

      # Letter followed by period or colon: "A. " or "A:"
      Regex.match?(~r/^([A-Da-d])[.:]\s/, response) ->
        case Regex.run(~r/^([A-Da-d])[.:]\s/, response) do
          [_, letter] -> String.upcase(letter)
          _ -> nil
        end

      true ->
        nil
    end
  end

  @doc """
  Parse binary QA response (yes/no/maybe).

  ## Examples

      MedlumLlm.Eval.Prompts.parse_binary_response("yes")
      #=> "yes"

      MedlumLlm.Eval.Prompts.parse_binary_response("No, because...")
      #=> "no"

      MedlumLlm.Eval.Prompts.parse_binary_response("It's uncertain")
      #=> "maybe"

  """
  @spec parse_binary_response(String.t()) :: String.t() | nil
  def parse_binary_response(response) do
    response = response |> String.downcase() |> String.trim()

    cond do
      String.starts_with?(response, "yes") -> "yes"
      String.starts_with?(response, "no") -> "no"
      String.starts_with?(response, "maybe") -> "maybe"
      String.contains?(response, "yes") -> "yes"
      String.contains?(response, "no") and not String.contains?(response, "not") -> "no"
      String.contains?(response, "maybe") or String.contains?(response, "uncertain") -> "maybe"
      true -> nil
    end
  end

  @doc """
  Extract reasoning and final answer from chain-of-thought response.

  ## Examples

      result = MedlumLlm.Eval.Prompts.parse_cot_response(
        "Step 1: The symptoms suggest cardiac involvement. Therefore, the answer is A."
      )
      result.reasoning
      #=> "Step 1: The symptoms suggest cardiac involvement."
      result.answer
      #=> "A"

  """
  @spec parse_cot_response(String.t()) :: %{reasoning: String.t(), answer: String.t() | nil}
  def parse_cot_response(response) do
    # Split on common transition phrases
    parts = String.split(response, ~r/(?:therefore|thus|so|final answer|answer)[:\s]+/i, parts: 2)

    case parts do
      [reasoning, rest] ->
        answer = parse_mcq_response(rest)
        %{reasoning: String.trim(reasoning), answer: answer}
      [full] ->
        # No clear separation, try to extract answer from end
        answer = parse_mcq_response(full)
        %{reasoning: String.trim(full), answer: answer}
    end
  end

  @doc """
  Validate that a sample has required fields for a template.

  ## Examples

      MedlumLlm.Eval.Prompts.validate_sample(:zero_shot_mcq, %{question: "Q", options: ["A", "B"]})
      #=> :ok

      MedlumLlm.Eval.Prompts.validate_sample(:zero_shot_mcq, %{question: "Q"})
      #=> {:error, {:missing_fields, [:options]}}

  """
  @spec validate_sample(atom(), map()) :: :ok | {:error, {:missing_fields, [atom()]}}
  def validate_sample(template_name, sample) do
    required_fields = required_fields_for(template_name)
    sample_keys = Map.keys(sample) |> MapSet.new()
    required_set = MapSet.new(required_fields)

    missing = MapSet.difference(required_set, sample_keys) |> MapSet.to_list()

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  @doc """
  Get required fields for a template.

  ## Examples

      MedlumLlm.Eval.Prompts.required_fields_for(:zero_shot_mcq)
      #=> [:question, :options]

  """
  @spec required_fields_for(atom()) :: [atom()]
  def required_fields_for(template_name) do
    case template_name do
      :zero_shot_mcq -> [:question, :options]
      :few_shot_mcq -> [:question, :options, :examples]
      :chain_of_thought_mcq -> [:question, :options]
      :zero_shot_binary_qa -> [:question, :context]
      :reasoning_eval -> [:question]
      _ -> []
    end
  end

  @doc """
  Format options with letters (A, B, C, D).

  Useful when dataset provides options without letter prefixes.

  ## Examples

      MedlumLlm.Eval.Prompts.format_options(["First", "Second", "Third", "Fourth"])
      #=> ["A. First", "B. Second", "C. Third", "D. Fourth"]

  """
  @spec format_options([String.t()]) :: [String.t()]
  def format_options(options) do
    letters = ~w(A B C D E F G H)

    options
    |> Enum.zip(letters)
    |> Enum.map(fn {option, letter} -> "#{letter}. #{option}" end)
  end

  @doc """
  Check if options already have letter prefixes.

  ## Examples

      MedlumLlm.Eval.Prompts.options_have_letters?(["A. First", "B. Second"])
      #=> true

      MedlumLlm.Eval.Prompts.options_have_letters?(["First", "Second"])
      #=> false

  """
  @spec options_have_letters?([String.t()]) :: boolean()
  def options_have_letters?(options) do
    Enum.all?(options, fn opt ->
      Regex.match?(~r/^[A-Ha-h][.:]\s/, opt)
    end)
  end

  @doc """
  Normalize sample to ensure options have letter prefixes.

  ## Examples

      sample = %{question: "Q?", options: ["First", "Second"]}
      normalized = MedlumLlm.Eval.Prompts.normalize_sample(sample)
      normalized.options
      #=> ["A. First", "B. Second"]

  """
  @spec normalize_sample(map()) :: map()
  def normalize_sample(sample) do
    if Map.has_key?(sample, :options) do
      options = sample[:options] || sample["options"]
      if options && not options_have_letters?(options) do
        Map.put(sample, :options, format_options(options))
      else
        sample
      end
    else
      sample
    end
  end

  # =========================================================================
  # Private Helpers
  # =========================================================================

  defp sample_to_assigns(sample) when is_map(sample) do
    sample
    |> Enum.map(fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
    end)
  end
end
