defmodule MedlumLlm.Labeling.NLI do
  @moduledoc """
  Types and validation for Natural Language Inference (NLI) classification.

  NLI is the core labeling paradigm for Clinical Verification Layer (CVL)
  hallucination detection. It classifies premise-hypothesis pairs into three
  categories:

  - **Entailment**: The hypothesis is supported by the premise (claim is verified)
  - **Contradiction**: The hypothesis contradicts the premise (hallucination detected)
  - **Neutral**: The hypothesis is neither supported nor contradicted (insufficient evidence)

  ## Example

      iex> MedlumLlm.Labeling.NLI.verdict_to_label(:entailment)
      "ENTAILMENT"

      iex> MedlumLlm.Labeling.NLI.label_to_verdict("CONTRADICTION")
      {:ok, :contradiction}

      iex> MedlumLlm.Labeling.NLI.valid_label?("NEUTRAL")
      true

  """

  @typedoc """
  NLI verdict as an atom.

  Represents the classification result of comparing a hypothesis against a premise:
  - `:entailment` - hypothesis follows from premise
  - `:contradiction` - hypothesis contradicts premise
  - `:neutral` - insufficient evidence to determine
  """
  @type verdict :: :entailment | :contradiction | :neutral

  @valid_labels ["ENTAILMENT", "CONTRADICTION", "NEUTRAL"]

  @verdict_to_label_map %{
    entailment: "ENTAILMENT",
    contradiction: "CONTRADICTION",
    neutral: "NEUTRAL"
  }

  @label_to_verdict_map %{
    "ENTAILMENT" => :entailment,
    "CONTRADICTION" => :contradiction,
    "NEUTRAL" => :neutral
  }

  @doc """
  Converts a verdict atom to its string label representation.

  ## Examples

      iex> MedlumLlm.Labeling.NLI.verdict_to_label(:entailment)
      "ENTAILMENT"

      iex> MedlumLlm.Labeling.NLI.verdict_to_label(:contradiction)
      "CONTRADICTION"

      iex> MedlumLlm.Labeling.NLI.verdict_to_label(:neutral)
      "NEUTRAL"

  """
  @spec verdict_to_label(verdict()) :: String.t()
  def verdict_to_label(verdict) when verdict in [:entailment, :contradiction, :neutral] do
    Map.fetch!(@verdict_to_label_map, verdict)
  end

  @doc """
  Parses a string label into its verdict atom representation.

  Returns `{:ok, verdict}` for valid labels, `{:error, :invalid_label}` otherwise.

  ## Examples

      iex> MedlumLlm.Labeling.NLI.label_to_verdict("ENTAILMENT")
      {:ok, :entailment}

      iex> MedlumLlm.Labeling.NLI.label_to_verdict("INVALID")
      {:error, :invalid_label}

  """
  @spec label_to_verdict(String.t()) :: {:ok, verdict()} | {:error, :invalid_label}
  def label_to_verdict(label) when is_binary(label) do
    case Map.fetch(@label_to_verdict_map, label) do
      {:ok, verdict} -> {:ok, verdict}
      :error -> {:error, :invalid_label}
    end
  end

  def label_to_verdict(_), do: {:error, :invalid_label}

  @doc """
  Parses a string label into its verdict atom representation, raising on invalid input.

  ## Examples

      iex> MedlumLlm.Labeling.NLI.label_to_verdict!("CONTRADICTION")
      :contradiction

  Raises `ArgumentError` for invalid labels.
  """
  @spec label_to_verdict!(String.t()) :: verdict()
  def label_to_verdict!(label) do
    case label_to_verdict(label) do
      {:ok, verdict} -> verdict
      {:error, :invalid_label} -> raise ArgumentError, "Invalid NLI label: #{inspect(label)}"
    end
  end

  @doc """
  Checks if a string is a valid NLI label.

  ## Examples

      iex> MedlumLlm.Labeling.NLI.valid_label?("ENTAILMENT")
      true

      iex> MedlumLlm.Labeling.NLI.valid_label?("entailment")
      false

      iex> MedlumLlm.Labeling.NLI.valid_label?("INVALID")
      false

  """
  @spec valid_label?(String.t()) :: boolean()
  def valid_label?(label) when is_binary(label), do: label in @valid_labels
  def valid_label?(_), do: false

  @doc """
  Returns the list of valid NLI label strings.

  ## Examples

      iex> MedlumLlm.Labeling.NLI.valid_labels()
      ["ENTAILMENT", "CONTRADICTION", "NEUTRAL"]

  """
  @spec valid_labels() :: [String.t()]
  def valid_labels, do: @valid_labels

  @doc """
  Returns the list of valid verdict atoms.

  ## Examples

      iex> MedlumLlm.Labeling.NLI.valid_verdicts()
      [:entailment, :contradiction, :neutral]

  """
  @spec valid_verdicts() :: [verdict()]
  def valid_verdicts, do: [:entailment, :contradiction, :neutral]

  @doc """
  Checks if an atom is a valid NLI verdict.

  ## Examples

      iex> MedlumLlm.Labeling.NLI.valid_verdict?(:entailment)
      true

      iex> MedlumLlm.Labeling.NLI.valid_verdict?(:unknown)
      false

  """
  @spec valid_verdict?(atom()) :: boolean()
  def valid_verdict?(verdict) when is_atom(verdict), do: verdict in valid_verdicts()
  def valid_verdict?(_), do: false
end
