defmodule ClinicalNerEx.Extractors.Diagnosis.Patterns do
  @moduledoc """
  Diagnosis extraction patterns for rule-based extraction.

  This module provides regex patterns and parsing utilities for extracting
  diagnosis and condition information from clinical text using a rule-based approach.

  ## Pattern Categories

  - **History pattern**: Matches "h/o hypertension" or "history of diabetes"
  - **Suspected/rule out pattern**: Matches "suspected MI" or "r/o PE"
  - **Severity pattern**: Matches "severe COPD" or "mild depression"
  - **Laterality pattern**: Matches "left knee OA" or "bilateral pneumonia"
  - **Acuity pattern**: Matches "acute on chronic kidney disease"
  - **Abbreviation lookup**: Expands known medical abbreviations

  ## Examples

      iex> Patterns.extract("h/o hypertension")
      [{0, 16, %{"condition" => "hypertension"}, :historical}]

      iex> Patterns.expand_abbreviation("HTN")
      "hypertension"

      iex> Patterns.detect_status("suspected MI")
      :suspected
  """

  # History pattern: "h/o hypertension" or "history of diabetes"
  @history_pattern ~r/
    (?:h\/o|hx\s+of|hx|history\s+of|past\s+(?:history\s+of|medical\s+history[:\s]+))
    \s*
    (?<condition>[A-Za-z][A-Za-z0-9\s\-\/]+?)
    (?:\s*[,\.]|\s+(?:and|with|on|controlled|uncontrolled)|$)
  /ix

  # Suspected/rule out pattern
  @suspected_pattern ~r/
    (?:suspected|possible|probable|\?|r\/o|rule\s+out|concerning\s+for)
    \s+
    (?<condition>[A-Za-z][A-Za-z0-9\s\-\/]+?)
    (?:\s*[,\.]|\s+(?:and|with)|$)
  /ix

  # Diagnosis with severity: "severe COPD" or "mild depression"
  @severity_pattern ~r/
    (?<severity>mild|moderate|severe|advanced|significant)
    \s+
    (?<condition>[A-Za-z][A-Za-z0-9\s\-]+?)
    (?:\s*[,\.]|\s+(?:and|with|on)|$)
  /ix

  # Laterality pattern: "left knee OA" or "bilateral pneumonia"
  @laterality_pattern ~r/
    (?<laterality>left|right|bilateral|L|R|B\/L)
    \s+
    (?<body_site>[A-Za-z]+)
    \s+
    (?<condition>[A-Za-z][A-Za-z0-9\s\-]+?)
    (?:\s*[,\.]|\s+(?:and|with)|$)
  /ix

  # Acute/chronic pattern
  @acuity_pattern ~r/
    (?<acuity>acute|chronic|acute\s+on\s+chronic)
    \s+
    (?<condition>[A-Za-z][A-Za-z0-9\s\-]+?)
    (?:\s*[,\.]|\s+(?:and|with)|$)
  /ix

  # Status indicator patterns (defined as functions to avoid module attribute issues with Regex)
  defp status_pattern(:active), do: ~r/\b(?:active|current|ongoing|present)\s+/i
  defp status_pattern(:resolved), do: ~r/\b(?:resolved|cured|healed|recovered)\s+/i
  defp status_pattern(:historical), do: ~r/\b(?:h\/o|hx|history\s+of|past\s+history|pmh[:\s])/i
  defp status_pattern(:suspected), do: ~r/(?:\b(?:suspected|possible|probable|likely)\s+|\?\s*)/i
  defp status_pattern(:ruled_out), do: ~r/\b(?:r\/o|ruled\s+out|no\s+evidence\s+of|negative\s+for)\s+/i

  # Common abbreviations
  @abbreviations %{
    "htn" => "hypertension",
    "dm" => "diabetes mellitus",
    "t2dm" => "type 2 diabetes mellitus",
    "t1dm" => "type 1 diabetes mellitus",
    "chf" => "congestive heart failure",
    "cad" => "coronary artery disease",
    "copd" => "chronic obstructive pulmonary disease",
    "ckd" => "chronic kidney disease",
    "esrd" => "end stage renal disease",
    "mi" => "myocardial infarction",
    "cva" => "cerebrovascular accident",
    "tia" => "transient ischemic attack",
    "dvt" => "deep vein thrombosis",
    "pe" => "pulmonary embolism",
    "gerd" => "gastroesophageal reflux disease",
    "uti" => "urinary tract infection",
    "uri" => "upper respiratory infection",
    "pna" => "pneumonia",
    "osa" => "obstructive sleep apnea",
    "oa" => "osteoarthritis",
    "ra" => "rheumatoid arthritis",
    "sle" => "systemic lupus erythematosus",
    "afib" => "atrial fibrillation",
    "a-fib" => "atrial fibrillation",
    "hld" => "hyperlipidemia",
    "bph" => "benign prostatic hyperplasia"
  }

  @doc """
  Extract all diagnosis mentions from text.

  Returns a list of tuples containing `{start_offset, end_offset, captures, type}` where
  captures is a map of named capture groups and type indicates the pattern matched.

  ## Examples

      iex> Patterns.extract("h/o hypertension")
      [{0, 16, %{"condition" => "hypertension"}, :historical}]

      iex> Patterns.extract("Patient has HTN and DM")
      [{12, 15, %{"condition" => "HTN"}, :abbreviation}, ...]
  """
  @spec extract(String.t()) :: [{non_neg_integer(), non_neg_integer(), map(), atom()}]
  def extract(text) do
    results = []

    # Try history pattern
    results = results ++ extract_with_pattern(text, @history_pattern, :historical)

    # Try suspected/rule out pattern
    results = results ++ extract_with_pattern(text, @suspected_pattern, :suspected)

    # Try severity pattern
    results = results ++ extract_with_pattern(text, @severity_pattern, :with_severity)

    # Try laterality pattern
    results = results ++ extract_with_pattern(text, @laterality_pattern, :with_laterality)

    # Try acuity pattern
    results = results ++ extract_with_pattern(text, @acuity_pattern, :with_acuity)

    # Try abbreviation lookup
    results = results ++ extract_abbreviations(text)

    # Deduplicate and sort
    results
    |> Enum.uniq_by(fn {start, _end, _match, _type} -> start end)
    |> Enum.sort_by(fn {start, _end, _match, _type} -> start end)
  end

  @doc """
  Parse a diagnosis match into attributes.

  Takes the raw captures from regex matching and normalizes them into
  a consistent attribute map.

  ## Examples

      iex> match = %{"condition" => "hypertension", "severity" => nil}
      iex> Patterns.parse_match(match, :historical)
      %{condition: "hypertension", status: :historical, severity: nil, ...}
  """
  @spec parse_match(map(), atom()) :: map()
  def parse_match(match, type) do
    condition = normalize_condition(match["condition"])

    %{
      condition: condition,
      status: parse_status(type, match),
      severity: parse_severity(match["severity"]),
      body_site: match["body_site"],
      laterality: parse_laterality(match["laterality"]),
      onset: nil
    }
  end

  @doc """
  Expand abbreviation to full condition name.

  ## Examples

      iex> Patterns.expand_abbreviation("HTN")
      "hypertension"

      iex> Patterns.expand_abbreviation("unknown")
      "unknown"
  """
  @spec expand_abbreviation(String.t()) :: String.t()
  def expand_abbreviation(abbrev) do
    Map.get(@abbreviations, String.downcase(abbrev), abbrev)
  end

  @doc """
  Detect status from surrounding context.

  ## Examples

      iex> Patterns.detect_status("h/o diabetes")
      :historical

      iex> Patterns.detect_status("suspected PE")
      :suspected

      iex> Patterns.detect_status("diabetes mellitus")
      :active
  """
  @spec detect_status(String.t()) :: atom()
  def detect_status(text) do
    cond do
      Regex.match?(status_pattern(:ruled_out), text) -> :ruled_out
      Regex.match?(status_pattern(:suspected), text) -> :suspected
      Regex.match?(status_pattern(:historical), text) -> :historical
      Regex.match?(status_pattern(:resolved), text) -> :resolved
      Regex.match?(status_pattern(:active), text) -> :active
      true -> :active
    end
  end

  @doc """
  Returns the abbreviations map for external use.
  """
  @spec abbreviations() :: map()
  def abbreviations, do: @abbreviations

  @doc """
  Returns the history pattern regex for external use.
  """
  @spec history_pattern() :: Regex.t()
  def history_pattern, do: @history_pattern

  @doc """
  Returns the suspected pattern regex for external use.
  """
  @spec suspected_pattern() :: Regex.t()
  def suspected_pattern, do: @suspected_pattern

  @doc """
  Returns the severity pattern regex for external use.
  """
  @spec severity_pattern() :: Regex.t()
  def severity_pattern, do: @severity_pattern

  # Private functions

  defp extract_with_pattern(text, pattern, type) do
    case Regex.scan(pattern, text, return: :index) do
      [] ->
        []

      matches ->
        Enum.map(matches, fn [{start, length} | _rest] ->
          match_text = String.slice(text, start, length)
          captures = Regex.named_captures(pattern, match_text) || %{}
          {start, start + length, captures, type}
        end)
        |> Enum.filter(fn {_s, _e, m, _t} ->
          condition = m["condition"]
          condition && String.length(String.trim(condition)) > 2
        end)
    end
  end

  defp extract_abbreviations(text) do
    @abbreviations
    |> Map.keys()
    |> Enum.flat_map(fn abbrev ->
      # Case insensitive search for abbreviation as whole word
      pattern = ~r/\b#{Regex.escape(abbrev)}\b/i

      case Regex.scan(pattern, text, return: :index) do
        [] ->
          []

        matches ->
          Enum.map(matches, fn [{start, length}] ->
            matched_text = String.slice(text, start, length)
            {start, start + length, %{"condition" => matched_text}, :abbreviation}
          end)
      end
    end)
  end

  defp normalize_condition(nil), do: nil

  defp normalize_condition(condition) do
    normalized =
      condition
      |> String.trim()
      |> String.downcase()

    expand_abbreviation(normalized)
  end

  defp parse_status(:historical, _match), do: :historical
  defp parse_status(:suspected, _match), do: :suspected
  defp parse_status(:abbreviation, _match), do: :active
  defp parse_status(_, _), do: :active

  defp parse_severity(nil), do: nil
  defp parse_severity(""), do: nil

  defp parse_severity(severity) do
    case String.downcase(severity) do
      s when s in ["mild", "minimal", "slight"] -> :mild
      s when s in ["moderate", "moderately"] -> :moderate
      s when s in ["severe", "advanced", "significant", "serious"] -> :severe
      _ -> nil
    end
  end

  defp parse_laterality(nil), do: nil
  defp parse_laterality(""), do: nil

  defp parse_laterality(lat) do
    case String.downcase(lat) do
      l when l in ["left", "l", "lt"] -> :left
      r when r in ["right", "r", "rt"] -> :right
      b when b in ["bilateral", "b/l", "both"] -> :bilateral
      _ -> nil
    end
  end
end
