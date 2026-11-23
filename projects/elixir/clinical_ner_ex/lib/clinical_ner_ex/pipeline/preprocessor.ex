defmodule ClinicalNerEx.Pipeline.Preprocessor do
  @moduledoc """
  Text preprocessing for NER extraction.

  Handles text normalization, sentence segmentation, and tokenization
  to prepare clinical text for entity extraction.

  ## Processing Steps

  1. **Whitespace normalization** - Collapse multiple spaces
  2. **Unicode normalization** - Replace special characters with ASCII equivalents
  3. **Abbreviation expansion** - Expand common clinical abbreviations
  4. **Sentence segmentation** - Split text into sentences

  ## Examples

      iex> {:ok, preprocessed} = ClinicalNerEx.Pipeline.Preprocessor.process("Patient w/ HTN")
      iex> preprocessed.normalized
      "Patient with HTN"
  """

  @doc """
  Process text for extraction.

  Returns a map containing:
  - `original` - The original input text
  - `normalized` - The normalized text
  - `sentences` - List of segmented sentences

  ## Examples

      iex> {:ok, result} = ClinicalNerEx.Pipeline.Preprocessor.process("Patient on metformin.")
      iex> result.original
      "Patient on metformin."
      iex> result.normalized
      "Patient on metformin."
  """
  @spec process(String.t()) :: {:ok, map()} | {:error, term()}
  def process(text) when is_binary(text) do
    normalized =
      text
      |> normalize_whitespace()
      |> normalize_unicode()
      |> expand_common_abbreviations()

    sentences = segment_sentences(normalized)

    {:ok,
     %{
       original: text,
       normalized: normalized,
       sentences: sentences
     }}
  rescue
    e -> {:error, {:preprocessing_failed, Exception.message(e)}}
  end

  def process(_), do: {:error, :invalid_input}

  @doc """
  Normalize whitespace in text.

  Collapses multiple spaces into single spaces and trims leading/trailing whitespace.

  ## Examples

      iex> ClinicalNerEx.Pipeline.Preprocessor.normalize_whitespace("Patient   on    metformin")
      "Patient on metformin"
  """
  @spec normalize_whitespace(String.t()) :: String.t()
  def normalize_whitespace(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  Normalize unicode characters.

  Replaces common unicode characters with ASCII equivalents for consistent processing.

  ## Examples

      iex> ClinicalNerEx.Pipeline.Preprocessor.normalize_unicode("metformin\u20141000mg")
      "metformin-1000mg"
  """
  @spec normalize_unicode(String.t()) :: String.t()
  def normalize_unicode(text) do
    text
    # Dashes
    |> String.replace("\u2013", "-")
    |> String.replace("\u2014", "-")
    |> String.replace("\u2212", "-")
    # Quotes
    |> String.replace("\u2018", "'")
    |> String.replace("\u2019", "'")
    |> String.replace("\u201C", "\"")
    |> String.replace("\u201D", "\"")
    # Spaces
    |> String.replace("\u00A0", " ")
    # Arrows
    |> String.replace("\u2192", "->")
    |> String.replace("\u2190", "<-")
  end

  @doc """
  Expand common clinical abbreviations.

  Expands abbreviations that help with extraction while preserving
  medical abbreviations that are commonly used (HTN, DM, etc.).

  ## Examples

      iex> ClinicalNerEx.Pipeline.Preprocessor.expand_common_abbreviations("w/ HTN")
      "with HTN"
  """
  @spec expand_common_abbreviations(String.t()) :: String.t()
  def expand_common_abbreviations(text) do
    text
    # Common clinical abbreviations that aid extraction
    |> String.replace(~r/\bw\/\b/i, "with")
    |> String.replace(~r/\bw\/o\b/i, "without")
    |> String.replace(~r/\bs\/p\b/i, "status post")
    |> String.replace(~r/\bc\/o\b/i, "complains of")
    |> String.replace(~r/\br\/o\b/i, "rule out")
    |> String.replace(~r/\bd\/c\b/i, "discontinue")
    |> String.replace(~r/\bf\/u\b/i, "follow up")
    |> String.replace(~r/\bpt\b(?!\.)/, "patient")
    # Preserve medical abbreviations - don't expand
    # HTN, DM, COPD, etc. are left as-is for the extractors to handle
  end

  @doc """
  Segment text into sentences.

  Uses simple heuristics to split clinical text into sentences,
  accounting for common abbreviations that include periods.

  ## Examples

      iex> ClinicalNerEx.Pipeline.Preprocessor.segment_sentences("Patient on metformin. Labs normal.")
      ["Patient on metformin.", "Labs normal."]
  """
  @spec segment_sentences(String.t()) :: [String.t()]
  def segment_sentences(text) do
    # Protect common abbreviations with periods
    protected =
      text
      |> protect_abbreviations()

    # Split on sentence boundaries
    protected
    |> String.split(~r/(?<=[.!?])\s+(?=[A-Z])/)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&restore_abbreviations/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Protect abbreviations that contain periods
  defp protect_abbreviations(text) do
    text
    |> String.replace(~r/\bDr\./i, "Dr<<DOT>>")
    |> String.replace(~r/\bMr\./i, "Mr<<DOT>>")
    |> String.replace(~r/\bMrs\./i, "Mrs<<DOT>>")
    |> String.replace(~r/\bMs\./i, "Ms<<DOT>>")
    |> String.replace(~r/\be\.g\./i, "e<<DOT>>g<<DOT>>")
    |> String.replace(~r/\bi\.e\./i, "i<<DOT>>e<<DOT>>")
    |> String.replace(~r/\betc\./i, "etc<<DOT>>")
    |> String.replace(~r/\bvs\./i, "vs<<DOT>>")
    |> String.replace(~r/\bmg\./i, "mg<<DOT>>")
    |> String.replace(~r/\bml\./i, "ml<<DOT>>")
  end

  # Restore protected abbreviations
  defp restore_abbreviations(text) do
    String.replace(text, "<<DOT>>", ".")
  end
end
