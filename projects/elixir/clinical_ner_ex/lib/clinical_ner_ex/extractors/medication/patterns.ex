defmodule ClinicalNerEx.Extractors.Medication.Patterns do
  @moduledoc """
  Medication extraction patterns for rule-based extraction.

  This module provides regex patterns and parsing utilities for extracting
  medication information from clinical text using a rule-based approach.

  ## Pattern Categories

  - **Full medication pattern**: Drug name + dose + unit + optional route + optional frequency
  - **Drug + dose pattern**: Simplified pattern for drug name and dosage only
  - **PRN pattern**: Detects "as needed" indicators
  - **Duration pattern**: Extracts treatment duration

  ## Examples

      iex> Patterns.extract("metformin 500 mg PO BID")
      [{0, 23, %{"drug_name" => "metformin", "dose" => "500", ...}}]

      iex> Patterns.prn?("tylenol 500mg PRN for pain")
      true

      iex> Patterns.extract_duration("for 7 days")
      "7 days"
  """

  # Full medication pattern: drug + dose + unit + optional route + optional frequency
  # Use word boundary at start to avoid capturing preceding words
  @drug_dose_pattern ~r/
    \b(?<drug_name>[A-Za-z][A-Za-z0-9\-]+)
    \s+
    (?<dose>\d+(?:\.\d+)?)
    \s*
    (?<dose_unit>mg|mcg|g|mL|ml|units?|IU)
    (?:\s*(?<route>PO|po|IV|iv|SC|sc|IM|im|SL|sl|PR|pr|topical|inhaled))?
    (?:\s*(?<frequency>BID|bid|TID|tid|QID|qid|QD|qd|daily|q\d+h|once\s+daily|twice\s+daily|three\s+times\s+daily|at\s+bedtime|qhs|PRN|prn))?
  /x

  # Simplified pattern for drug + dose only
  # Use word boundary at start to avoid capturing preceding words
  @drug_dose_simple ~r/
    \b(?<drug_name>[A-Za-z][A-Za-z0-9\-]+)
    \s+
    (?<dose>\d+(?:\.\d+)?)
    \s*
    (?<dose_unit>mg|mcg|g|mL|ml|units?|IU)
  /x

  # Dose range pattern (e.g., "50-100 mg")
  @dose_range_pattern ~r/
    (?<dose_low>\d+(?:\.\d+)?)
    \s*-\s*
    (?<dose_high>\d+(?:\.\d+)?)
    \s*
    (?<dose_unit>mg|mcg|g|mL|ml|units?|IU)
  /x

  # PRN indicator (case insensitive)
  @prn_pattern ~r/\b(?:PRN|prn|as\s+needed|when\s+needed)\b/i

  # Duration pattern (case insensitive)
  @duration_pattern ~r/
    (?:for|x)\s*
    (?<duration_value>\d+)
    \s*
    (?<duration_unit>days?|weeks?|months?|d|wk|mo)
  /xi

  @frequency_map %{
    "bid" => "BID",
    "BID" => "BID",
    "tid" => "TID",
    "TID" => "TID",
    "qid" => "QID",
    "QID" => "QID",
    "qd" => "daily",
    "QD" => "daily",
    "daily" => "daily",
    "once daily" => "daily",
    "twice daily" => "BID",
    "three times daily" => "TID",
    "at bedtime" => "qhs",
    "qhs" => "qhs",
    "QHS" => "qhs",
    "prn" => "PRN",
    "PRN" => "PRN"
  }

  @route_map %{
    "po" => "PO",
    "PO" => "PO",
    "iv" => "IV",
    "IV" => "IV",
    "sc" => "SC",
    "SC" => "SC",
    "im" => "IM",
    "IM" => "IM",
    "sl" => "SL",
    "SL" => "SL",
    "pr" => "PR",
    "PR" => "PR",
    "topical" => "topical",
    "inhaled" => "inhaled"
  }

  @doc """
  Extract all medication mentions from text.

  Returns a list of tuples containing `{start_offset, end_offset, captures}` where
  captures is a map of named capture groups.

  ## Examples

      iex> Patterns.extract("metformin 500mg")
      [{0, 15, %{"drug_name" => "metformin", "dose" => "500", "dose_unit" => "mg", ...}}]

      iex> Patterns.extract("No medications")
      []
  """
  @spec extract(String.t()) :: [{non_neg_integer(), non_neg_integer(), map()}]
  def extract(text) do
    results = []

    # Try full pattern first
    results = results ++ extract_with_pattern(text, @drug_dose_pattern, :full)

    # Get the start offsets from full pattern results
    full_starts = MapSet.new(Enum.map(results, fn {start, _end, _match} -> start end))

    # Try simple drug+dose pattern for anything missed
    simple_results = extract_with_pattern(text, @drug_dose_simple, :simple)

    # Only add simple results that don't overlap with full results
    simple_filtered =
      Enum.reject(simple_results, fn {start, _end, _match} ->
        MapSet.member?(full_starts, start)
      end)

    results = results ++ simple_filtered

    # Deduplicate by start offset and sort
    results
    |> Enum.uniq_by(fn {start, _end, _match} -> start end)
    |> Enum.sort_by(fn {start, _end, _match} -> start end)
  end

  @doc """
  Parse a medication match into normalized attributes.

  Takes the raw captures from regex matching and normalizes them into
  a consistent attribute map.

  ## Examples

      iex> match = %{"drug_name" => "Metformin", "dose" => "500", "dose_unit" => "MG"}
      iex> Patterns.parse_match(match)
      %{drug_name: "metformin", dose: 500.0, dose_unit: "mg", ...}
  """
  @spec parse_match(map()) :: map()
  def parse_match(match) do
    %{
      drug_name: normalize_drug_name(match["drug_name"]),
      dose: parse_dose(match["dose"]),
      dose_unit: normalize_unit(match["dose_unit"]),
      route: normalize_route(match["route"]),
      frequency: normalize_frequency(match["frequency"]),
      prn: false
    }
  end

  @doc """
  Check if text contains PRN (as needed) indicator.

  ## Examples

      iex> Patterns.prn?("tylenol 500mg PRN for pain")
      true

      iex> Patterns.prn?("metformin 500mg BID")
      false
  """
  @spec prn?(String.t()) :: boolean()
  def prn?(text) do
    Regex.match?(@prn_pattern, text)
  end

  @doc """
  Extract duration from text.

  ## Examples

      iex> Patterns.extract_duration("for 7 days")
      "7 days"

      iex> Patterns.extract_duration("x 2 weeks")
      "2 weeks"

      iex> Patterns.extract_duration("no duration")
      nil
  """
  @spec extract_duration(String.t()) :: String.t() | nil
  def extract_duration(text) do
    case Regex.named_captures(@duration_pattern, text) do
      nil ->
        nil

      %{"duration_value" => value, "duration_unit" => unit} ->
        "#{value} #{normalize_duration_unit(unit)}"
    end
  end

  @doc """
  Extract dose range from text.

  ## Examples

      iex> Patterns.extract_dose_range("50-100 mg")
      %{dose_low: 50.0, dose_high: 100.0, dose_unit: "mg"}

      iex> Patterns.extract_dose_range("500 mg")
      nil
  """
  @spec extract_dose_range(String.t()) :: map() | nil
  def extract_dose_range(text) do
    case Regex.named_captures(@dose_range_pattern, text) do
      nil ->
        nil

      captures ->
        %{
          dose_low: parse_dose(captures["dose_low"]),
          dose_high: parse_dose(captures["dose_high"]),
          dose_unit: normalize_unit(captures["dose_unit"])
        }
    end
  end

  @doc """
  Returns the full pattern regex for external use.
  """
  @spec full_pattern() :: Regex.t()
  def full_pattern, do: @drug_dose_pattern

  @doc """
  Returns the simple pattern regex for external use.
  """
  @spec simple_pattern() :: Regex.t()
  def simple_pattern, do: @drug_dose_simple

  @doc """
  Returns the frequency normalization map.
  """
  @spec frequency_map() :: map()
  def frequency_map, do: @frequency_map

  @doc """
  Returns the route normalization map.
  """
  @spec route_map() :: map()
  def route_map, do: @route_map

  # Private functions

  defp extract_with_pattern(text, pattern, _type) do
    # Use Regex.scan with return: :index to get positions
    case Regex.scan(pattern, text, return: :index) do
      [] ->
        []

      matches ->
        Enum.map(matches, fn [{start, length} | _rest] ->
          match_text = String.slice(text, start, length)
          captures = Regex.named_captures(pattern, match_text) || %{}
          {start, start + length, captures}
        end)
    end
  end

  defp normalize_drug_name(nil), do: nil
  defp normalize_drug_name(""), do: nil

  defp normalize_drug_name(name) do
    name
    |> String.trim()
    |> String.downcase()
  end

  defp parse_dose(nil), do: nil
  defp parse_dose(""), do: nil

  defp parse_dose(dose) when is_binary(dose) do
    case Float.parse(dose) do
      {value, _} -> value
      :error -> nil
    end
  end

  defp normalize_unit(nil), do: nil
  defp normalize_unit(""), do: nil

  defp normalize_unit(unit) do
    unit
    |> String.downcase()
    |> case do
      "ml" -> "mL"
      "iu" -> "IU"
      "unit" -> "units"
      other -> other
    end
  end

  defp normalize_route(nil), do: nil
  defp normalize_route(""), do: nil

  defp normalize_route(route) do
    route_lower = String.downcase(route)
    Map.get(@route_map, route_lower, route)
  end

  defp normalize_frequency(nil), do: nil
  defp normalize_frequency(""), do: nil

  defp normalize_frequency(freq) do
    freq_lower = String.downcase(String.trim(freq))
    Map.get(@frequency_map, freq_lower, freq)
  end

  defp normalize_duration_unit(unit) do
    case String.downcase(unit) do
      "d" -> "days"
      "day" -> "days"
      "wk" -> "weeks"
      "week" -> "weeks"
      "mo" -> "months"
      "month" -> "months"
      other -> other
    end
  end
end
