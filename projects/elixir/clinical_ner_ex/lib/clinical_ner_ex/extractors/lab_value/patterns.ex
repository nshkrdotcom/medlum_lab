defmodule ClinicalNerEx.Extractors.LabValue.Patterns do
  @moduledoc """
  Lab value extraction patterns for rule-based extraction.

  This module provides regex patterns and parsing utilities for extracting
  laboratory test values from clinical text using a rule-based approach.

  ## Pattern Categories

  - **Lab with reference range**: Lab name + value + unit + reference range (most specific)
  - **Lab with value**: Lab name + value + optional unit + optional abnormal flag
  - **Electrolyte shorthand**: Common electrolyte panel format (Na 138, K 4.2)
  - **Percentage value**: Labs expressed as percentages (A1c 7.2%)

  ## Lab Name Normalization

  Lab names are normalized to canonical forms using an alias dictionary.
  For example, "HbA1c", "A1c", and "hemoglobin a1c" all normalize to "hemoglobin a1c".

  ## Examples

      iex> Patterns.extract("A1c 7.2%")
      [{0, 8, %{"lab_name" => "A1c", "value" => "7.2"}, :percentage}]

      iex> Patterns.extract("WBC 8.5 (4.5-11.0)")
      [{0, 18, %{"lab_name" => "WBC", "value" => "8.5", "ref_low" => "4.5", "ref_high" => "11.0"}, :with_reference}]

      iex> Patterns.canonical_name("Cr")
      "creatinine"
  """

  # Lab with reference range: "WBC 8.5 (4.5-11.0)" or "Hemoglobin 12.5 g/dL (12.0-16.0)"
  @lab_with_reference ~r/
    \b(?<lab_name>[A-Za-z][A-Za-z0-9\s\-\/]{0,30}?)
    \s*[:=]?\s*
    (?<value>\d+(?:\.\d+)?)
    \s*
    (?<unit>mg\/dL|g\/dL|mmol\/L|mEq\/L|U\/L|IU\/L|%|10\^[36]\/[um]L|[kKmM]\/[um]L|ng\/mL|pg\/mL|mIU\/L|uIU\/mL|seconds?|sec|ratio|fL|pg)?
    \s*
    \((?<ref_low>\d+(?:\.\d+)?)\s*[-–]\s*(?<ref_high>\d+(?:\.\d+)?)\)
  /ix

  # Lab value pattern: drug + value + optional unit + optional flag
  @lab_value_pattern ~r/
    \b(?<lab_name>[A-Za-z][A-Za-z0-9\s\-\/]{0,30}?)
    \s*[:=]?\s*
    (?<value>\d+(?:\.\d+)?)
    \s*
    (?<unit>mg\/dL|g\/dL|mmol\/L|mEq\/L|U\/L|IU\/L|%|10\^[36]\/[um]L|[kKmM]\/[um]L|ng\/mL|pg\/mL|mIU\/L|uIU\/mL|seconds?|sec|ratio|fL|pg)?
    (?:\s*\((?<flag>H|L|HH|LL|HIGH|LOW|HI|LO)\))?
  /ix

  # Electrolyte panel shorthand: "Na 138, K 4.2, Cl 102"
  @electrolyte_pattern ~r/
    \b(?<lab_name>Na|K|Cl|CO2|Ca|Mg|Phos|BUN|Cr|Glu)
    \s+
    (?<value>\d+(?:\.\d+)?)
    (?:\s*\((?<flag>H|L|HH|LL|HIGH|LOW|HI|LO)\))?
  /ix

  # Percentage pattern (for A1c, Hct, etc.)
  @percentage_pattern ~r/
    \b(?<lab_name>[A-Za-z][A-Za-z0-9\s]{0,20}?)
    \s*[:=]?\s*
    (?<value>\d+(?:\.\d+)?)\s*%
    (?:\s*\((?<flag>H|L|HH|LL|HIGH|LOW|HI|LO)\))?
  /ix

  # Known lab name aliases (lowercase) -> canonical name
  @lab_aliases %{
    # Hemoglobin A1c
    "a1c" => "hemoglobin a1c",
    "hba1c" => "hemoglobin a1c",
    "hgb a1c" => "hemoglobin a1c",
    "hemoglobin a1c" => "hemoglobin a1c",
    "glycated hemoglobin" => "hemoglobin a1c",
    # Glucose
    "glu" => "glucose",
    "glucose" => "glucose",
    "blood glucose" => "glucose",
    "fasting glucose" => "glucose",
    "fbs" => "glucose",
    "rbs" => "glucose",
    # Creatinine
    "cr" => "creatinine",
    "crea" => "creatinine",
    "creatinine" => "creatinine",
    "serum creatinine" => "creatinine",
    # BUN
    "bun" => "blood urea nitrogen",
    "blood urea nitrogen" => "blood urea nitrogen",
    "urea nitrogen" => "blood urea nitrogen",
    # Electrolytes
    "na" => "sodium",
    "na+" => "sodium",
    "sodium" => "sodium",
    "k" => "potassium",
    "k+" => "potassium",
    "potassium" => "potassium",
    "cl" => "chloride",
    "cl-" => "chloride",
    "chloride" => "chloride",
    "co2" => "carbon dioxide",
    "carbon dioxide" => "carbon dioxide",
    "bicarbonate" => "carbon dioxide",
    "bicarb" => "carbon dioxide",
    # Hemoglobin and Hematocrit
    "hgb" => "hemoglobin",
    "hb" => "hemoglobin",
    "hemoglobin" => "hemoglobin",
    "hct" => "hematocrit",
    "hematocrit" => "hematocrit",
    # CBC
    "wbc" => "white blood cell count",
    "white blood cell count" => "white blood cell count",
    "white blood cells" => "white blood cell count",
    "white count" => "white blood cell count",
    "leukocytes" => "white blood cell count",
    "rbc" => "red blood cell count",
    "red blood cell count" => "red blood cell count",
    "erythrocytes" => "red blood cell count",
    "plt" => "platelets",
    "platelets" => "platelets",
    "platelet count" => "platelets",
    # Thyroid
    "tsh" => "thyroid stimulating hormone",
    "thyroid stimulating hormone" => "thyroid stimulating hormone",
    "ft4" => "free t4",
    "free t4" => "free t4",
    # Lipid Panel
    "cholesterol" => "total cholesterol",
    "total cholesterol" => "total cholesterol",
    "tc" => "total cholesterol",
    "hdl" => "hdl cholesterol",
    "hdl cholesterol" => "hdl cholesterol",
    "hdl-c" => "hdl cholesterol",
    "ldl" => "ldl cholesterol",
    "ldl cholesterol" => "ldl cholesterol",
    "ldl-c" => "ldl cholesterol",
    "trig" => "triglycerides",
    "tg" => "triglycerides",
    "triglycerides" => "triglycerides",
    # Liver Function
    "alt" => "alanine aminotransferase",
    "sgpt" => "alanine aminotransferase",
    "alanine aminotransferase" => "alanine aminotransferase",
    "ast" => "aspartate aminotransferase",
    "sgot" => "aspartate aminotransferase",
    "aspartate aminotransferase" => "aspartate aminotransferase",
    "alp" => "alkaline phosphatase",
    "alk phos" => "alkaline phosphatase",
    "alkaline phosphatase" => "alkaline phosphatase",
    "tbili" => "total bilirubin",
    "bilirubin" => "total bilirubin",
    "total bilirubin" => "total bilirubin",
    "alb" => "albumin",
    "albumin" => "albumin",
    "tp" => "total protein",
    "total protein" => "total protein",
    "protein" => "total protein",
    # Coagulation
    "inr" => "international normalized ratio",
    "international normalized ratio" => "international normalized ratio",
    "pt" => "prothrombin time",
    "prothrombin time" => "prothrombin time",
    "ptt" => "partial thromboplastin time",
    "aptt" => "partial thromboplastin time",
    "partial thromboplastin time" => "partial thromboplastin time",
    # Renal
    "egfr" => "estimated glomerular filtration rate",
    "gfr" => "estimated glomerular filtration rate",
    "estimated gfr" => "estimated glomerular filtration rate",
    # Minerals
    "ca" => "calcium",
    "ca2+" => "calcium",
    "calcium" => "calcium",
    "mg" => "magnesium",
    "mg2+" => "magnesium",
    "magnesium" => "magnesium",
    "phos" => "phosphorus",
    "phosphate" => "phosphorus",
    "phosphorus" => "phosphorus"
  }

  @flag_normalization %{
    "high" => "H",
    "hi" => "H",
    "h" => "H",
    "low" => "L",
    "lo" => "L",
    "l" => "L",
    "hh" => "HH",
    "ll" => "LL"
  }

  @doc """
  Extract all lab value mentions from text.

  Returns a list of tuples containing `{start_offset, end_offset, captures, pattern_type}`
  where captures is a map of named capture groups and pattern_type indicates which
  pattern matched.

  Pattern types:
  - `:with_reference` - Lab with reference range (highest confidence)
  - `:standard` - Lab with value and optional unit/flag
  - `:electrolyte` - Electrolyte shorthand format
  - `:percentage` - Percentage value format

  ## Examples

      iex> Patterns.extract("A1c 7.2%")
      [{0, 8, %{"lab_name" => "A1c", "value" => "7.2"}, :percentage}]

      iex> Patterns.extract("Na 138, K 4.2")
      [{0, 6, %{...}, :electrolyte}, {8, 14, %{...}, :electrolyte}]
  """
  @spec extract(String.t()) :: [{non_neg_integer(), non_neg_integer(), map(), atom()}]
  def extract(text) do
    results = []

    # Try lab with reference range pattern first (most specific)
    results = results ++ extract_with_pattern(text, @lab_with_reference, :with_reference)

    # Get positions already matched by reference pattern to avoid duplicates
    matched_positions = MapSet.new(Enum.map(results, fn {start, _, _, _} -> start end))

    # Try percentage pattern
    percentage_results =
      text
      |> extract_with_pattern(@percentage_pattern, :percentage)
      |> Enum.reject(fn {start, _, _, _} -> MapSet.member?(matched_positions, start) end)

    results = results ++ percentage_results
    matched_positions = update_matched_positions(matched_positions, percentage_results)

    # Try electrolyte shorthand
    electrolyte_results =
      text
      |> extract_with_pattern(@electrolyte_pattern, :electrolyte)
      |> Enum.reject(fn {start, _, _, _} -> MapSet.member?(matched_positions, start) end)

    results = results ++ electrolyte_results
    matched_positions = update_matched_positions(matched_positions, electrolyte_results)

    # Try standard lab value pattern
    standard_results =
      text
      |> extract_with_pattern(@lab_value_pattern, :standard)
      |> Enum.reject(fn {start, _, _, _} -> MapSet.member?(matched_positions, start) end)

    results = results ++ standard_results

    # Deduplicate by start offset, prefer more complete matches
    results
    |> Enum.group_by(fn {start, _end, _match, _type} -> start end)
    |> Enum.map(fn {_start, matches} ->
      Enum.max_by(matches, &match_score/1)
    end)
    |> Enum.sort_by(fn {start, _end, _match, _type} -> start end)
  end

  # Scores a match for deduplication - prefer more complete matches
  defp match_score({_start, _end, match, type}) do
    base = type_score(type)
    unit_bonus = if match["unit"], do: 5, else: 0
    flag_bonus = if match["flag"], do: 2, else: 0
    ref_bonus = if match["ref_low"], do: 8, else: 0
    base + unit_bonus + flag_bonus + ref_bonus
  end

  @doc """
  Parse a lab value match into normalized attributes.

  Takes the raw captures from regex matching and normalizes them into
  a consistent attribute map.

  ## Examples

      iex> match = %{"lab_name" => "A1c", "value" => "7.2"}
      iex> Patterns.parse_match(match, :percentage)
      %{lab_name: "hemoglobin a1c", value: 7.2, unit: "%", ...}
  """
  @spec parse_match(map(), atom()) :: map()
  def parse_match(match, type) do
    %{
      lab_name: normalize_lab_name(match["lab_name"]),
      value: parse_value(match["value"]),
      unit: normalize_unit(match["unit"], type),
      reference_low: parse_value(match["ref_low"]),
      reference_high: parse_value(match["ref_high"]),
      abnormal_flag: normalize_flag(match["flag"])
    }
  end

  @doc """
  Get the canonical lab name from an alias.

  Lab names are normalized to lowercase and mapped to their canonical form.

  ## Examples

      iex> Patterns.canonical_name("A1c")
      "hemoglobin a1c"

      iex> Patterns.canonical_name("Cr")
      "creatinine"

      iex> Patterns.canonical_name("unknown lab")
      "unknown lab"
  """
  @spec canonical_name(String.t()) :: String.t()
  def canonical_name(name) do
    normalized = String.downcase(String.trim(name))
    Map.get(@lab_aliases, normalized, normalized)
  end

  @doc """
  Check if a string is a known lab name.

  ## Examples

      iex> Patterns.known_lab?("A1c")
      true

      iex> Patterns.known_lab?("random text")
      false
  """
  @spec known_lab?(String.t()) :: boolean()
  def known_lab?(name) do
    normalized = String.downcase(String.trim(name))
    Map.has_key?(@lab_aliases, normalized)
  end

  @doc """
  Returns the lab aliases map for external use.
  """
  @spec lab_aliases() :: map()
  def lab_aliases, do: @lab_aliases

  @doc """
  Returns the flag normalization map for external use.
  """
  @spec flag_normalization() :: map()
  def flag_normalization, do: @flag_normalization

  # Private functions

  defp extract_with_pattern(text, pattern, type) do
    case Regex.scan(pattern, text, return: :index) do
      [] ->
        []

      matches ->
        matches
        |> Enum.map(fn [{start, length} | _rest] ->
          match_text = String.slice(text, start, length)
          captures = Regex.named_captures(pattern, match_text) || %{}
          {start, start + length, captures, type}
        end)
        |> Enum.filter(fn {_s, _e, m, _t} ->
          # Filter out false positives
          lab_name = m["lab_name"]
          value = m["value"]
          lab_name && value && String.trim(lab_name) != "" && known_lab?(lab_name)
        end)
    end
  end

  defp update_matched_positions(positions, results) do
    Enum.reduce(results, positions, fn {start, _, _, _}, acc ->
      MapSet.put(acc, start)
    end)
  end

  defp type_score(:with_reference), do: 20
  defp type_score(:percentage), do: 15
  defp type_score(:electrolyte), do: 12
  defp type_score(:standard), do: 10

  defp normalize_lab_name(nil), do: nil
  defp normalize_lab_name(""), do: nil

  defp normalize_lab_name(name) do
    name
    |> String.trim()
    |> canonical_name()
  end

  defp parse_value(nil), do: nil
  defp parse_value(""), do: nil

  defp parse_value(value) when is_binary(value) do
    case Float.parse(value) do
      {v, _} -> v
      :error -> nil
    end
  end

  defp normalize_unit(nil, :percentage), do: "%"
  defp normalize_unit(nil, :electrolyte), do: "mEq/L"
  defp normalize_unit(nil, _), do: nil
  defp normalize_unit("", :percentage), do: "%"
  defp normalize_unit("", :electrolyte), do: "mEq/L"
  defp normalize_unit("", _), do: nil

  @unit_normalization %{
    "mg/dl" => "mg/dL",
    "g/dl" => "g/dL",
    "mmol/l" => "mmol/L",
    "meq/l" => "mEq/L",
    "u/l" => "U/L",
    "iu/l" => "IU/L",
    "miu/l" => "mIU/L",
    "uiu/ml" => "uIU/mL",
    "ng/ml" => "ng/mL",
    "pg/ml" => "pg/mL",
    "k/ul" => "K/uL",
    "m/ul" => "M/uL",
    "sec" => "seconds",
    "second" => "seconds",
    "fl" => "fL"
  }

  defp normalize_unit(unit, _type) do
    unit
    |> String.trim()
    |> String.replace(~r/\s+/, "")
    |> normalize_unit_case()
  end

  defp normalize_unit_case(unit) do
    lower = String.downcase(unit)
    Map.get(@unit_normalization, lower, lower)
  end

  defp normalize_flag(nil), do: nil
  defp normalize_flag(""), do: nil

  defp normalize_flag(flag) do
    normalized = String.downcase(String.trim(flag))
    Map.get(@flag_normalization, normalized, String.upcase(flag))
  end
end
