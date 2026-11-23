defmodule MedlumLlm.PII.Clinical do
  @moduledoc """
  Clinical/healthcare PII detection and redaction patterns.

  This module provides healthcare-specific PII redaction capabilities for
  HIPAA compliance. It detects and redacts PHI (Protected Health
  Information) that is commonly found in clinical text.

  ## Pattern Tiers

  Patterns are organized into two modes:

  - **Standard** - High-confidence patterns for common clinical identifiers
    (MRN, DOB, NPI, DEA, Medicare/Medicaid, insurance IDs, medical dates)

  - **Aggressive** - Standard patterns plus context-dependent patterns
    (provider names, facility names, street addresses)

  ## Usage

      # Get all standard patterns
      patterns = MedlumLlm.PII.Clinical.patterns()

      # Get all patterns including aggressive ones
      patterns = MedlumLlm.PII.Clinical.aggressive_patterns()

      # Redact text using standard mode
      redacted = MedlumLlm.PII.Clinical.redact("MRN: 12345678", :standard)
      # => "[MRN_REDACTED]"

      # Redact text using aggressive mode
      redacted = MedlumLlm.PII.Clinical.redact("Dr. Smith", :aggressive)
      # => "[PROVIDER_REDACTED]"

  ## Pattern Format

  Each pattern is a tuple of `{regex, replacement}` where:
  - `regex` - Compiled regex pattern to match
  - `replacement` - Replacement string (e.g., "[MRN_REDACTED]")
  """

  @type pattern :: {Regex.t(), String.t()}
  @type redaction_mode :: :standard | :aggressive

  @doc """
  Returns standard clinical PII patterns.

  These patterns detect high-confidence clinical identifiers:
  - Medical Record Numbers (MRN)
  - Date of Birth (DOB)
  - National Provider Identifier (NPI)
  - DEA Number
  - Medicare/Medicaid IDs
  - Insurance IDs (policy, member, group, subscriber)
  - Medical dates (admission, discharge, service, visit)
  - Room/Bed numbers

  ## Examples

      iex> patterns = MedlumLlm.PII.Clinical.patterns()
      iex> length(patterns) > 0
      true

      iex> patterns = MedlumLlm.PII.Clinical.patterns()
      iex> text = "MRN: 12345678"
      iex> Enum.reduce(patterns, text, fn {regex, repl}, acc -> Regex.replace(regex, acc, repl) end)
      "[MRN_REDACTED]"
  """
  @spec patterns() :: [pattern()]
  def patterns do
    mrn_patterns() ++
      dob_patterns() ++
      npi_patterns() ++
      dea_patterns() ++
      medicare_medicaid_patterns() ++
      insurance_patterns() ++
      medical_date_patterns() ++
      room_bed_patterns()
  end

  @doc """
  Returns aggressive clinical PII patterns.

  Includes all standard patterns plus context-dependent patterns:
  - Provider names (Dr. prefix, MD/DO/NP/PA credentials)
  - Facility names (Hospital, Medical Center, Clinic, Health System)
  - Street addresses

  Use this mode for exports where higher recall is preferred over precision.

  ## Examples

      iex> patterns = MedlumLlm.PII.Clinical.aggressive_patterns()
      iex> length(patterns) > length(MedlumLlm.PII.Clinical.patterns())
      true
  """
  @spec aggressive_patterns() :: [pattern()]
  def aggressive_patterns do
    patterns() ++ provider_patterns() ++ facility_patterns() ++ address_patterns()
  end

  @doc """
  Redacts clinical PII from text using the specified mode.

  ## Parameters

  - `text` - The text to redact
  - `mode` - Redaction mode (`:standard` or `:aggressive`), defaults to `:standard`

  ## Examples

      iex> MedlumLlm.PII.Clinical.redact("MRN: 12345678")
      "[MRN_REDACTED]"

      iex> MedlumLlm.PII.Clinical.redact("MRN: 12345678", :standard)
      "[MRN_REDACTED]"

      iex> MedlumLlm.PII.Clinical.redact("Patient DOB: 01/15/1980", :standard)
      "Patient [DOB_REDACTED]"

      iex> MedlumLlm.PII.Clinical.redact("Dr. Smith ordered labs", :aggressive)
      "[PROVIDER_REDACTED] ordered labs"
  """
  @spec redact(String.t(), redaction_mode()) :: String.t()
  def redact(text, mode \\ :standard)

  def redact(text, mode) when is_binary(text) do
    selected_patterns =
      case mode do
        :standard -> patterns()
        :aggressive -> aggressive_patterns()
        _ -> patterns()
      end

    Enum.reduce(selected_patterns, text, fn {regex, replacement}, acc ->
      Regex.replace(regex, acc, replacement)
    end)
  end

  def redact(text, _mode), do: text

  @doc """
  Detects clinical PII types present in text.

  Returns a list of detected PII type atoms.

  ## Examples

      iex> MedlumLlm.PII.Clinical.detect("MRN: 12345678")
      [:mrn]

      iex> MedlumLlm.PII.Clinical.detect("DOB: 01/15/1980, NPI: 1234567890")
      [:dob, :npi]

      iex> MedlumLlm.PII.Clinical.detect("No PII here")
      []
  """
  @spec detect(String.t()) :: [atom()]
  def detect(text) when is_binary(text) do
    detection_patterns()
    |> Enum.reduce([], fn {type, regex}, acc ->
      if Regex.match?(regex, text) do
        [type | acc]
      else
        acc
      end
    end)
    |> Enum.uniq()
    |> Enum.reverse()
  end

  def detect(_), do: []

  @doc """
  Returns a list of all detectable clinical PII types.
  """
  @spec pii_types() :: [atom()]
  def pii_types do
    [
      :mrn,
      :dob,
      :npi,
      :dea,
      :medicare,
      :medicaid,
      :insurance_id,
      :medical_date,
      :room_bed,
      :provider_name,
      :facility_name,
      :address
    ]
  end

  # Pattern groups

  defp mrn_patterns do
    [
      # MRN with explicit label
      {~r/\bMRN[:\s#]*\d{5,12}\b/i, "[MRN_REDACTED]"},
      # Medical record / chart number
      {~r/\b(?:medical\s+record|chart)\s*(?:number|#|id)?[:\s]*\d{5,12}\b/i, "[MRN_REDACTED]"},
      # Patient ID / Pt ID / Acct
      {~r/\b(?:patient\s+id|pt\s*id|acct)[:\s#]*[A-Z0-9]{5,15}\b/i, "[MRN_REDACTED]"}
    ]
  end

  defp dob_patterns do
    [
      # DOB with explicit label (MM/DD/YYYY or MM-DD-YYYY)
      {~r/\bDOB[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/i, "[DOB_REDACTED]"},
      # Date of birth spelled out
      {~r/\b(?:date\s+of\s+birth|birth\s*date)[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/i,
       "[DOB_REDACTED]"},
      # DOB with ISO format (YYYY-MM-DD)
      {~r/\bDOB[:\s]*\d{4}[\/\-]\d{1,2}[\/\-]\d{1,2}\b/i, "[DOB_REDACTED]"}
    ]
  end

  defp npi_patterns do
    [
      # National Provider Identifier (10 digits)
      {~r/\bNPI[:\s#]*\d{10}\b/i, "[NPI_REDACTED]"}
    ]
  end

  defp dea_patterns do
    [
      # DEA Number (2 letters + 7 digits)
      {~r/\bDEA[:\s#]*[A-Z]{2}\d{7}\b/i, "[DEA_REDACTED]"}
    ]
  end

  defp medicare_medicaid_patterns do
    [
      # Medicare HICN format (9 digits + letter + optional digit)
      {~r/\b(?:HIC|HICN|Medicare(?:\s+ID)?)[:\s#]*\d{9}[A-Z]\d?\b/i, "[MEDICARE_REDACTED]"},
      # Medicare Beneficiary Identifier (MBI) - new format
      {~r/\bMBI[:\s#]*[1-9][A-Z](?:[A-Z0-9]){2}\-?[A-Z0-9]{3}\-?[A-Z0-9]{4}\b/i,
       "[MEDICARE_REDACTED]"},
      # Medicaid ID
      {~r/\bMedicaid(?:\s+ID)?[:\s#]*[A-Z0-9]{8,15}\b/i, "[MEDICAID_REDACTED]"}
    ]
  end

  defp insurance_patterns do
    [
      # Policy ID
      {~r/\b(?:policy)\s*(?:id|#|number)?[:\s]*[A-Z0-9]{8,20}\b/i, "[INSURANCE_REDACTED]"},
      # Member ID
      {~r/\b(?:member)\s*(?:id|#|number)?[:\s]*[A-Z0-9]{8,20}\b/i, "[INSURANCE_REDACTED]"},
      # Subscriber ID
      {~r/\b(?:subscriber)\s*(?:id|#|number)?[:\s]*[A-Z0-9]{8,20}\b/i, "[INSURANCE_REDACTED]"},
      # Group ID (shorter, more specific context)
      {~r/\b(?:group)\s*(?:id|#|number)?[:\s]*[A-Z0-9]{6,15}\b/i, "[INSURANCE_REDACTED]"}
    ]
  end

  defp medical_date_patterns do
    [
      # Admission date
      {~r/\b(?:admit(?:ted)?|admission)[:\s]*(?:date)?[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/i,
       "[DATE_REDACTED]"},
      # Discharge date
      {~r/\b(?:discharge[d]?)[:\s]*(?:date)?[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/i,
       "[DATE_REDACTED]"},
      # Service/visit/encounter date
      {~r/\b(?:service|visit|encounter)[:\s]*(?:date)?[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/i,
       "[DATE_REDACTED]"},
      # DOA/DOD abbreviations
      {~r/\b(?:DOA|DOD)[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/i, "[DATE_REDACTED]"},
      # Procedure/surgery date
      {~r/\b(?:procedure|surgery)[:\s]*(?:date)?[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/i,
       "[DATE_REDACTED]"}
    ]
  end

  defp room_bed_patterns do
    [
      # Room number
      {~r/\b(?:room|rm\.?)\s*(?:#|number)?[:\s]*\d{1,4}[A-Z]?\b/i, "[ROOM_REDACTED]"},
      # Bed number
      {~r/\bbed\s*(?:#|number)?[:\s]*\d{1,2}[A-Z]?\b/i, "[ROOM_REDACTED]"},
      # Unit designation
      {~r/\bunit\s*(?:#|number)?[:\s]*\d{1,4}[A-Z]?\b/i, "[ROOM_REDACTED]"}
    ]
  end

  defp provider_patterns do
    [
      # Dr. prefix
      {~r/\bDr\.?\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?\b/, "[PROVIDER_REDACTED]"},
      # Name with credentials (MD, DO, NP, PA, RN, PhD, APRN)
      {~r/\b[A-Z][a-z]+(?:\s+[A-Z]\.?)?\s+[A-Z][a-z]+,?\s*(?:MD|DO|NP|PA|RN|PhD|APRN)\b/,
       "[PROVIDER_REDACTED]"},
      # Explicit role with name
      {~r/\b(?:attending|referring|treating|ordering)\s+(?:physician|doctor|provider)[:\s]+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?\b/i,
       "[PROVIDER_REDACTED]"}
    ]
  end

  defp facility_patterns do
    [
      # Hospital/Medical Center/Clinic with name
      {~r/\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s+(?:Hospital|Medical\s+Center|Clinic|Health\s+(?:System|Center)|Regional\s+Medical)\b/,
       "[FACILITY_REDACTED]"},
      # Common hospital name patterns
      {~r/\b(?:St\.?|Saint)\s+[A-Z][a-z]+(?:'s)?\s+(?:Hospital|Medical|Health)\b/,
       "[FACILITY_REDACTED]"}
    ]
  end

  defp address_patterns do
    [
      # Street address (number + street name + suffix)
      {~r/\b\d{1,5}\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?\s+(?:St(?:reet)?|Ave(?:nue)?|Rd|Road|Blvd|Boulevard|Dr(?:ive)?|Ln|Lane|Ct|Court|Pl|Place|Way)\b\.?/i,
       "[ADDRESS_REDACTED]"}
    ]
  end

  # Detection patterns (for detect/1)
  defp detection_patterns do
    [
      {:mrn, ~r/\bMRN[:\s#]*\d{5,12}\b/i},
      {:mrn, ~r/\b(?:medical\s+record|chart|patient\s+id|pt\s*id)[:\s#]*[A-Z0-9]{5,15}\b/i},
      {:dob, ~r/\bDOB[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/i},
      {:dob, ~r/\b(?:date\s+of\s+birth|birth\s*date)[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/i},
      {:npi, ~r/\bNPI[:\s#]*\d{10}\b/i},
      {:dea, ~r/\bDEA[:\s#]*[A-Z]{2}\d{7}\b/i},
      {:medicare, ~r/\b(?:HIC|HICN|Medicare|MBI)[:\s#]*[A-Z0-9]{10,15}\b/i},
      {:medicaid, ~r/\bMedicaid[:\s#]*[A-Z0-9]{8,15}\b/i},
      {:insurance_id,
       ~r/\b(?:policy|member|subscriber|group)\s*(?:id|#|number)?[:\s]*[A-Z0-9]{6,20}\b/i},
      {:medical_date,
       ~r/\b(?:admitted|admit|discharge[d]?|service|DOA|DOD)[:\s]*(?:date)?[:\s]*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/i},
      {:room_bed, ~r/\b(?:room|rm|bed|unit)[:\s#]*\d{1,4}[A-Z]?\b/i},
      {:provider_name, ~r/\bDr\.?\s+[A-Z][a-z]+/},
      {:provider_name, ~r/\b[A-Z][a-z]+,?\s*(?:MD|DO|NP|PA)\b/},
      {:facility_name, ~r/\b[A-Z][a-z]+\s+(?:Hospital|Medical\s+Center|Clinic)\b/},
      {:address, ~r/\b\d{1,5}\s+[A-Z][a-z]+\s+(?:St|Ave|Rd|Blvd|Dr|Ln)\b/i}
    ]
  end
end
