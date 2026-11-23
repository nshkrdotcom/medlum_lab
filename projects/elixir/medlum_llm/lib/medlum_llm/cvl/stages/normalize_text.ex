defmodule MedlumLlm.CVL.Stages.NormalizeText do
  @moduledoc """
  Forge Stage for text normalization and cleaning.

  This stage prepares text for downstream processing by:
  - Normalizing Unicode encoding (NFC normalization)
  - Standardizing whitespace (multiple spaces to single, normalize line endings)
  - Removing control characters
  - Fixing common encoding issues (smart quotes, etc.)

  ## Configuration Options

  - `:normalize_unicode` - Apply NFC normalization (default: `true`)
  - `:fix_encoding` - Fix common encoding issues (default: `true`)
  - `:strip_control_chars` - Remove control characters (default: `true`)
  - `:normalize_whitespace` - Standardize whitespace (default: `true`)

  ## Example

      iex> sample = %Forge.Sample{data: %{source_document: "Hello  World\\r\\n"}}
      iex> {:ok, normalized} = NormalizeText.process(sample)
      iex> normalized.data.source_document
      "Hello World\\n"
  """

  @behaviour Forge.Stage

  @impl true
  @spec process(Forge.Sample.t()) :: {:ok, Forge.Sample.t()} | {:skip, term()} | {:error, term()}
  def process(sample) do
    data = sample.data

    normalized_data =
      data
      |> normalize_field(:source_document)
      |> normalize_field(:generated_summary)
      |> normalize_field(:question)
      |> normalize_field(:gold_answer)
      |> normalize_field(:predicted_answer)

    {:ok, %{sample | data: normalized_data}}
  rescue
    e ->
      {:error, %{reason: :normalization_failed, exception: Exception.message(e)}}
  end

  @impl true
  @spec async?() :: boolean()
  def async?, do: false

  @impl true
  @spec concurrency() :: pos_integer()
  def concurrency, do: 1

  @impl true
  @spec timeout() :: pos_integer()
  def timeout, do: 5_000

  # Private functions

  @spec normalize_field(map(), atom()) :: map()
  defp normalize_field(data, field) do
    case Map.get(data, field) do
      nil -> data
      value when is_binary(value) -> Map.put(data, field, normalize_text(value))
      _other -> data
    end
  end

  @spec normalize_text(String.t()) :: String.t()
  defp normalize_text(text) do
    text
    |> normalize_unicode()
    |> fix_encoding_issues()
    |> strip_control_characters()
    |> normalize_whitespace()
    |> String.trim()
  end

  @spec normalize_unicode(String.t()) :: String.t()
  defp normalize_unicode(text) do
    # Apply NFC (Canonical Decomposition, followed by Canonical Composition)
    :unicode.characters_to_nfc_binary(text)
  end

  @spec fix_encoding_issues(String.t()) :: String.t()
  defp fix_encoding_issues(text) do
    text
    # Smart quotes to regular quotes
    |> String.replace(["'", "'", "‚", "‛"], "'")
    |> String.replace(["\u201C", "\u201D", "\u201E", "\u201F"], "\"")
    # Em/en dashes to regular dashes
    |> String.replace(["—", "–", "−"], "-")
    # Ellipsis
    |> String.replace("…", "...")
    # Non-breaking spaces
    |> String.replace(["\u00A0", "\u2007", "\u202F"], " ")
    # Zero-width characters
    |> String.replace(["\u200B", "\u200C", "\u200D", "\uFEFF"], "")
    # Bullet points to standard dash
    |> String.replace(["•", "◦", "▪", "▸"], "-")
  end

  @spec strip_control_characters(String.t()) :: String.t()
  defp strip_control_characters(text) do
    # Remove control characters except newlines, tabs, and carriage returns
    # which will be handled by whitespace normalization
    Regex.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, text, "")
  end

  @spec normalize_whitespace(String.t()) :: String.t()
  defp normalize_whitespace(text) do
    text
    # Normalize line endings to Unix-style
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    # Replace multiple spaces with single space (but preserve newlines)
    |> String.replace(~r/[^\S\n]+/, " ")
    # Remove leading/trailing whitespace from each line
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.join("\n")
    # Collapse multiple blank lines to single blank line
    |> String.replace(~r/\n{3,}/, "\n\n")
  end
end
