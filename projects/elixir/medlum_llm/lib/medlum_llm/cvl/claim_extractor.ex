defmodule MedlumLlm.CVL.ClaimExtractor do
  @moduledoc """
  Extracts atomic claims from generated clinical summaries.

  This module splits summary text into individual verifiable claims for CVL verification.
  Claim extraction is **not** NER - it splits text into logical statements, not entities.

  ## Examples

      iex> summary = \"\"\"
      ...> - Started metformin 500mg twice daily
      ...> - HbA1c is 7.2%
      ...> - Diagnosed with type 2 diabetes
      ...> \"\"\"
      iex> claims = ClaimExtractor.extract(summary)
      iex> length(claims)
      3
      iex> hd(claims).text
      "Started metformin 500mg twice daily"

  ## Splitting Strategy

  Claims are extracted by:
  1. Bullet points (`-`, `*`, `•`)
  2. Numbered items (`1.`, `2.`, etc.)
  3. Sentence boundaries (fallback when no structural markers)

  ## Output Format

  Each claim is a map:

      %{
        id: "c1",
        text: "Started metformin 500mg twice daily",
        source_offset: 0,
        source_length: 35
      }

  """

  @type claim :: %{
          id: String.t(),
          text: String.t(),
          source_offset: non_neg_integer() | nil,
          source_length: non_neg_integer() | nil
        }

  @doc """
  Extract atomic claims from a summary text.

  ## Options

  - `:min_length` - Minimum claim length (default: 5)
  - `:max_length` - Maximum claim length (default: 500)

  ## Examples

      iex> ClaimExtractor.extract("Patient has diabetes. HbA1c is 7.2%.")
      [
        %{id: "c1", text: "Patient has diabetes.", source_offset: 0, source_length: 21},
        %{id: "c2", text: "HbA1c is 7.2%.", source_offset: 22, source_length: 14}
      ]

  """
  @spec extract(String.t(), keyword()) :: [claim()]
  def extract(summary, opts \\ []) do
    min_length = Keyword.get(opts, :min_length, 5)
    max_length = Keyword.get(opts, :max_length, 500)

    summary
    |> split_into_claims()
    |> Enum.filter(fn {text, _offset} ->
      len = String.length(text)
      len >= min_length and len <= max_length
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {{text, offset}, index} ->
      %{
        id: "c#{index}",
        text: text,
        source_offset: offset,
        source_length: String.length(text)
      }
    end)
  end

  @doc """
  Extract claims and return only the text (convenience function).

  ## Examples

      iex> ClaimExtractor.extract_texts("- Claim one\\n- Claim two")
      ["Claim one", "Claim two"]

  """
  @spec extract_texts(String.t(), keyword()) :: [String.t()]
  def extract_texts(summary, opts \\ []) do
    summary
    |> extract(opts)
    |> Enum.map(& &1.text)
  end

  # Primary splitting function that tries structured markers first
  defp split_into_claims(text) do
    cond do
      has_bullet_points?(text) ->
        split_by_bullets(text)

      has_numbered_items?(text) ->
        split_by_numbers(text)

      true ->
        split_by_sentences(text)
    end
  end

  # Detect if text has bullet point markers
  defp has_bullet_points?(text) do
    Regex.match?(~r/^[\s]*[-*•]\s+/m, text)
  end

  # Detect if text has numbered items
  defp has_numbered_items?(text) do
    Regex.match?(~r/^[\s]*\d+[.)]\s+/m, text)
  end

  # Split by bullet points (-, *, •)
  defp split_by_bullets(text) do
    # Split on bullet markers while tracking offset
    pattern = ~r/(?:^|\n)[\s]*[-*•][\s]+/

    split_with_offsets(text, pattern)
    |> Enum.map(fn {claim, offset} ->
      {normalize_claim(claim), offset}
    end)
    |> Enum.reject(fn {claim, _} -> claim == "" end)
  end

  # Split by numbered items (1., 2., 1), 2), etc.)
  defp split_by_numbers(text) do
    pattern = ~r/(?:^|\n)[\s]*\d+[.)]\s+/

    split_with_offsets(text, pattern)
    |> Enum.map(fn {claim, offset} ->
      {normalize_claim(claim), offset}
    end)
    |> Enum.reject(fn {claim, _} -> claim == "" end)
  end

  # Split by sentence boundaries
  defp split_by_sentences(text) do
    # Handle common sentence-ending punctuation
    # Be careful not to split on decimal points (e.g., "7.2%") or abbreviations
    pattern = ~r/(?<=[.!?])\s+(?=[A-Z])/

    split_with_offsets(text, pattern)
    |> Enum.map(fn {claim, offset} ->
      {normalize_claim(claim), offset}
    end)
    |> Enum.reject(fn {claim, _} -> claim == "" end)
  end

  # Split text while tracking original offsets
  defp split_with_offsets(text, pattern) do
    parts = Regex.split(pattern, text, include_captures: true)

    {claims, _final_offset} =
      Enum.reduce(parts, {[], 0}, fn part, {acc, offset} ->
        # Skip separator parts (they match the pattern)
        if Regex.match?(pattern, part) do
          {acc, offset + String.length(part)}
        else
          trimmed = String.trim(part)

          if trimmed == "" do
            {acc, offset + String.length(part)}
          else
            {[{trimmed, offset} | acc], offset + String.length(part)}
          end
        end
      end)

    Enum.reverse(claims)
  end

  # Normalize a claim by cleaning up whitespace and markers
  defp normalize_claim(text) do
    text
    |> String.trim()
    # Remove leading bullet/number markers that might remain
    |> String.replace(~r/^[-*•]\s+/, "")
    |> String.replace(~r/^\d+[.)]\s+/, "")
    # Normalize internal whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
