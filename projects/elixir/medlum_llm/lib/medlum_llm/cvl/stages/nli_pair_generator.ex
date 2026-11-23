defmodule MedlumLlm.CVL.Stages.NLIPairGenerator do
  @moduledoc """
  Forge Stage for generating Natural Language Inference (NLI) pairs.

  This stage creates premise-hypothesis pairs from extracted claims for
  training the CVL NLI classifier. Each pair is labeled based on the
  relationship between the source document and the generated claim.

  ## NLI Labels

  - `:entailment` - Hypothesis is supported by the premise
  - `:contradiction` - Hypothesis contradicts the premise
  - `:neutral` - Hypothesis is neither entailed nor contradicted

  ## Label Mapping from Error Types

  | Error Type | NLI Label |
  |------------|-----------|
  | `:incorrect` | `:contradiction` |
  | `:contradiction` | `:contradiction` |
  | `:error` | `:neutral` |
  | `:low_confidence` | `:neutral` |
  | `:timeout` | `:neutral` |

  ## Example

      iex> sample = %Forge.Sample{data: %{
      ...>   source_document: "Patient has type 2 diabetes.",
      ...>   generated_summary: "Patient has type 1 diabetes.",
      ...>   error_type: :incorrect,
      ...>   claims: [%{text: "Patient has type 1 diabetes.", type: :diagnosis}]
      ...> }}
      iex> {:ok, with_nli} = NLIPairGenerator.process(sample)
      iex> hd(with_nli.data.nli_pairs).label
      :contradiction
  """

  @behaviour Forge.Stage

  @type nli_label :: :entailment | :contradiction | :neutral

  @type nli_pair :: %{
          premise: String.t(),
          hypothesis: String.t(),
          label: nli_label(),
          claim_type: atom(),
          confidence: float(),
          metadata: map()
        }

  # Error type to NLI label mapping
  @error_label_map %{
    incorrect: :contradiction,
    contradiction: :contradiction,
    error: :neutral,
    low_confidence: :neutral,
    timeout: :neutral,
    crash: :neutral
  }

  @impl true
  @spec process(Forge.Sample.t()) :: {:ok, Forge.Sample.t()} | {:skip, term()} | {:error, term()}
  def process(sample) do
    data = sample.data

    # Get the base label from error type
    base_label = Map.get(@error_label_map, data[:error_type], :neutral)

    # Generate NLI pairs from claims
    nli_pairs = generate_pairs(data, base_label)

    if Enum.empty?(nli_pairs) do
      # Skip samples without any valid NLI pairs
      {:skip, :no_valid_pairs}
    else
      updated_data =
        data
        |> Map.put(:nli_pairs, nli_pairs)
        |> Map.put(:nli_label, base_label)

      {:ok, %{sample | data: updated_data}}
    end
  rescue
    e ->
      {:error, %{reason: :nli_generation_failed, exception: Exception.message(e)}}
  end

  @impl true
  @spec async?() :: boolean()
  def async?, do: false

  @impl true
  @spec concurrency() :: pos_integer()
  def concurrency, do: 1

  @impl true
  @spec timeout() :: pos_integer()
  def timeout, do: 30_000

  # Public helper functions

  @doc """
  Generate NLI pairs from sample data.

  Creates premise-hypothesis pairs where:
  - Premise is the source document or context
  - Hypothesis is each extracted claim from the generated text
  """
  @spec generate_pairs(map(), nli_label()) :: [nli_pair()]
  def generate_pairs(data, base_label) do
    premise = extract_premise(data)
    claims = data[:claims] || data[:generated_claims] || []

    claims
    |> Enum.filter(&valid_for_nli?/1)
    |> Enum.map(&build_nli_pair(&1, premise, base_label, data))
  end

  @doc """
  Map an error type to its corresponding NLI label.
  """
  @spec error_type_to_label(atom()) :: nli_label()
  def error_type_to_label(error_type) do
    Map.get(@error_label_map, error_type, :neutral)
  end

  # Private functions

  @spec extract_premise(map()) :: String.t()
  defp extract_premise(data) do
    # Priority: source_document > question + options > context
    cond do
      data[:source_document] && data[:source_document] != "" ->
        data[:source_document]

      data[:question] ->
        format_question_premise(data[:question], data[:options])

      data[:context] ->
        data[:context]

      true ->
        ""
    end
  end

  @spec format_question_premise(String.t(), map() | list() | nil) :: String.t()
  defp format_question_premise(question, nil), do: question

  defp format_question_premise(question, options) when is_map(options) do
    options_text =
      options
      |> Enum.map(fn {key, value} -> "#{key}) #{value}" end)
      |> Enum.join("\n")

    "#{question}\n\nOptions:\n#{options_text}"
  end

  defp format_question_premise(question, options) when is_list(options) do
    options_text =
      options
      |> Enum.with_index(fn opt, idx ->
        letter = <<(?A + idx)::utf8>>
        "#{letter}) #{opt}"
      end)
      |> Enum.join("\n")

    "#{question}\n\nOptions:\n#{options_text}"
  end

  defp format_question_premise(question, _), do: question

  @spec valid_for_nli?(map()) :: boolean()
  defp valid_for_nli?(%{text: text}) when is_binary(text) do
    # Claim must have meaningful content for NLI
    trimmed = String.trim(text)
    String.length(trimmed) >= 5 and String.contains?(trimmed, " ")
  end

  defp valid_for_nli?(_), do: false

  @spec build_nli_pair(map(), String.t(), nli_label(), map()) :: nli_pair()
  defp build_nli_pair(claim, premise, label, data) do
    # Convert claim text to hypothesis format
    hypothesis = format_hypothesis(claim[:text])

    # Compute confidence based on label certainty
    confidence = compute_pair_confidence(label, data)

    %{
      premise: premise,
      hypothesis: hypothesis,
      label: label,
      claim_type: claim[:type] || :general,
      confidence: confidence,
      metadata: %{
        claim_span: claim[:span],
        claim_index: claim[:index],
        error_type: data[:error_type],
        model: data[:model],
        benchmark: data[:benchmark],
        original_sample_id: data[:original_sample_id]
      }
    }
  end

  @spec format_hypothesis(String.t()) :: String.t()
  defp format_hypothesis(text) do
    text
    |> String.trim()
    # Ensure hypothesis ends with period
    |> ensure_ending_punctuation()
    # Capitalize first letter
    |> capitalize_first()
  end

  @spec ensure_ending_punctuation(String.t()) :: String.t()
  defp ensure_ending_punctuation(text) do
    if String.ends_with?(text, ["..", ".", "!", "?", ":"]) do
      text
    else
      text <> "."
    end
  end

  @spec capitalize_first(String.t()) :: String.t()
  defp capitalize_first(""), do: ""

  defp capitalize_first(<<first::utf8, rest::binary>>) do
    String.upcase(<<first::utf8>>) <> rest
  end

  @spec compute_pair_confidence(nli_label(), map()) :: float()
  defp compute_pair_confidence(label, data) do
    # Base confidence from error type certainty
    base =
      case data[:error_type] do
        :incorrect -> 0.9
        :contradiction -> 0.85
        :low_confidence -> 0.5
        :error -> 0.4
        _ -> 0.5
      end

    # Adjust based on label
    case label do
      :contradiction -> base
      :entailment -> base * 0.9
      :neutral -> base * 0.7
    end
  end
end
