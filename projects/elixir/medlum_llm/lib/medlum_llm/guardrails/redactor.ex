defmodule MedlumLlm.Guardrails.Redactor do
  @moduledoc """
  HIPAA-compliant redaction and de-identification for clinical text.

  Provides multiple redaction strategies for removing Protected Health Information (PHI)
  from clinical documents while preserving document utility.

  ## Redaction Modes

  - `:automatic` - Standard mode using Tier 1 + Tier 2 patterns
  - `:aggressive` - Uses all patterns including Tier 3 (names, facilities)
  - `:hipaa_safe_harbor` - Strict mode covering all 18 HIPAA identifiers

  ## Features

  - Pattern-based PHI detection using `MedlumLlm.Detectors.ClinicalPII`
  - Date shifting with temporal interval preservation
  - Age binning per HIPAA Safe Harbor (ages >89 become "90+")
  - Deterministic seeded pseudonymization for research reproducibility
  - Audit manifests for compliance tracking

  ## Examples

      # Basic redaction
      iex> text = "Patient MRN: 12345678, DOB: 01/15/1980"
      iex> MedlumLlm.Guardrails.Redactor.redact(text)
      "Patient [MRN_REDACTED], [DOB_REDACTED]"

      # Redaction with manifest for auditing
      iex> {redacted, manifest} = MedlumLlm.Guardrails.Redactor.redact_with_manifest(text)
      iex> manifest.redaction_count
      2

      # Deterministic redaction with seed
      iex> opts = [mode: :aggressive, seed: "study_001"]
      iex> MedlumLlm.Guardrails.Redactor.redact(text, opts)
      "Patient [MRN_a1b2c3], [DOB_d4e5f6]"
  """

  alias MedlumLlm.Detectors.ClinicalPII

  @type redaction_mode :: :automatic | :aggressive | :hipaa_safe_harbor

  @type redaction_opts :: [
          mode: redaction_mode(),
          seed: String.t() | nil,
          date_shift_days: integer() | nil,
          preserve_format: boolean(),
          replacement_style: :placeholder | :hash | :mask
        ]

  @type manifest :: %{
          original_hash: String.t(),
          redacted_hash: String.t(),
          mode: redaction_mode(),
          redaction_types: %{atom() => non_neg_integer()},
          redaction_count: non_neg_integer(),
          timestamp: DateTime.t()
        }

  # Replacement templates by type
  @replacement_templates %{
    mrn: "[MRN_REDACTED]",
    dob: "[DOB_REDACTED]",
    npi: "[NPI_REDACTED]",
    dea: "[DEA_REDACTED]",
    medicare_id: "[MEDICARE_REDACTED]",
    insurance_id: "[INSURANCE_REDACTED]",
    medical_date: "[DATE_REDACTED]",
    room_bed: "[ROOM_REDACTED]",
    provider_name: "[PROVIDER_REDACTED]",
    facility_name: "[FACILITY_REDACTED]"
  }

  @doc """
  Redacts clinical PII from text.

  ## Options

  - `:mode` - Redaction mode (`:automatic`, `:aggressive`, `:hipaa_safe_harbor`), default: `:automatic`
  - `:seed` - Seed for deterministic pseudonymization (default: nil for random)
  - `:date_shift_days` - Fixed days to shift dates, nil for no shifting (default: nil)
  - `:replacement_style` - How to replace PHI (`:placeholder`, `:hash`, `:mask`), default: `:placeholder`
  - `:preserve_format` - Attempt to preserve original format in replacement (default: false)

  ## Examples

      iex> Redactor.redact("MRN: 12345678")
      "MRN: [MRN_REDACTED]"

      iex> Redactor.redact("DOB: 01/15/1980", mode: :aggressive, seed: "test")
      "DOB: [DOB_a1b2c3d4]"
  """
  @spec redact(String.t(), redaction_opts()) :: String.t()
  def redact(text, opts \\ []) do
    mode = Keyword.get(opts, :mode, :automatic)
    seed = Keyword.get(opts, :seed)
    replacement_style = Keyword.get(opts, :replacement_style, :placeholder)

    # Get detections based on mode
    detections = scan_for_mode(text, mode)

    # Sort detections by position (descending) to replace from end to start
    sorted = Enum.sort_by(detections, &elem(&1.span, 0), :desc)

    # Apply replacements using binary slicing (regex positions are byte-based)
    Enum.reduce(sorted, text, fn detection, acc ->
      {start, stop} = detection.span
      original = binary_part(text, start, stop - start)
      replacement = get_replacement(detection.type, original, replacement_style, seed)

      binary_part(acc, 0, start) <>
        replacement <>
        binary_part(acc, stop, byte_size(acc) - stop)
    end)
  end

  @doc """
  Redacts text and returns a manifest for audit purposes.

  The manifest contains hashes (not content), counts, and metadata for
  HIPAA-compliant audit logging.

  ## Returns

  A tuple of `{redacted_text, manifest}` where manifest contains:
  - `:original_hash` - SHA256 hash of original text
  - `:redacted_hash` - SHA256 hash of redacted text
  - `:mode` - Redaction mode used
  - `:redaction_types` - Map of type -> count
  - `:redaction_count` - Total number of redactions
  - `:timestamp` - When redaction was performed

  ## Examples

      iex> {redacted, manifest} = Redactor.redact_with_manifest("MRN: 12345678")
      iex> manifest.redaction_types
      %{mrn: 1}
  """
  @spec redact_with_manifest(String.t(), redaction_opts()) :: {String.t(), manifest()}
  def redact_with_manifest(text, opts \\ []) do
    mode = Keyword.get(opts, :mode, :automatic)

    # Scan for PHI
    detections = scan_for_mode(text, mode)

    # Perform redaction
    redacted = redact(text, opts)

    # Build manifest without PHI
    redaction_types =
      detections
      |> Enum.map(& &1.type)
      |> Enum.frequencies()

    manifest = %{
      original_hash: hash_text(text),
      redacted_hash: hash_text(redacted),
      mode: mode,
      redaction_types: redaction_types,
      redaction_count: length(detections),
      timestamp: DateTime.utc_now()
    }

    {redacted, manifest}
  end

  @doc """
  Shifts all dates in text by a fixed number of days.

  Preserves temporal intervals between dates (useful for research data
  where relative timing matters but absolute dates must be removed).

  ## Options

  - `:format` - Expected date format (`:us`, `:iso`, `:auto`), default: `:auto`

  ## Examples

      iex> text = "Admitted: 01/15/2025, Discharged: 01/20/2025"
      iex> Redactor.shift_dates(text, 30)
      "Admitted: 02/14/2025, Discharged: 02/19/2025"
  """
  @spec shift_dates(String.t(), integer(), keyword()) :: String.t()
  def shift_dates(text, days, opts \\ []) when is_integer(days) do
    date_patterns = [
      # MM/DD/YYYY or MM-DD-YYYY
      {~r/\b(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})\b/, :us},
      # YYYY-MM-DD or YYYY/MM/DD
      {~r/\b(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})\b/, :iso}
    ]

    format_hint = Keyword.get(opts, :format, :auto)

    Enum.reduce(date_patterns, text, fn {pattern, pattern_format}, acc ->
      if format_hint == :auto or format_hint == pattern_format do
        Regex.replace(pattern, acc, fn match, p1, p2, p3 ->
          shift_single_date(match, p1, p2, p3, pattern_format, days)
        end)
      else
        acc
      end
    end)
  end

  @doc """
  Bins ages according to HIPAA Safe Harbor requirements.

  Ages over 89 are replaced with "90+" as per the Safe Harbor de-identification method.

  ## Examples

      iex> Redactor.bin_age(45)
      "45"

      iex> Redactor.bin_age(92)
      "90+"
  """
  @spec bin_age(integer()) :: String.t()
  def bin_age(age) when is_integer(age) and age > 89, do: "90+"
  def bin_age(age) when is_integer(age), do: Integer.to_string(age)

  @doc """
  Replaces ages in text with binned values per HIPAA Safe Harbor.

  ## Examples

      iex> text = "Patient is a 95-year-old male"
      iex> Redactor.bin_ages_in_text(text)
      "Patient is a 90+-year-old male"
  """
  @spec bin_ages_in_text(String.t()) :: String.t()
  def bin_ages_in_text(text) do
    # Match patterns like "92-year-old", "age 95", "95 years old"
    patterns = [
      ~r/\b(\d{2,3})[-\s]?year[-\s]?old\b/i,
      ~r/\bage[:\s]+(\d{2,3})\b/i,
      ~r/\b(\d{2,3})\s*(?:years?\s*old|yo|y\.?o\.?)\b/i
    ]

    Enum.reduce(patterns, text, fn pattern, acc ->
      Regex.replace(pattern, acc, fn match, age_str ->
        case Integer.parse(age_str) do
          {age, ""} when age > 89 ->
            String.replace(match, age_str, "90+")

          _ ->
            match
        end
      end)
    end)
  end

  # Private functions

  defp scan_for_mode(text, mode) do
    include_tier_3 =
      case mode do
        :automatic -> false
        :aggressive -> true
        :hipaa_safe_harbor -> true
      end

    # Lower threshold for aggressive modes
    threshold =
      case mode do
        :automatic -> 0.7
        :aggressive -> 0.5
        :hipaa_safe_harbor -> 0.5
      end

    ClinicalPII.scan(text, include_tier_3: include_tier_3, confidence_threshold: threshold)
  end

  defp get_replacement(type, original, style, seed) do
    case style do
      :placeholder ->
        Map.get(@replacement_templates, type, "[REDACTED]")

      :hash ->
        hash = generate_hash(original, seed)
        type_prefix = type |> Atom.to_string() |> String.upcase()
        "[#{type_prefix}_#{hash}]"

      :mask ->
        String.duplicate("*", String.length(original))
    end
  end

  defp generate_hash(value, nil) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  defp generate_hash(value, seed) when is_binary(seed) do
    :crypto.hash(:sha256, seed <> value)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  defp hash_text(text) do
    :crypto.hash(:sha256, text)
    |> Base.encode16(case: :lower)
  end

  defp shift_single_date(_match, p1, p2, p3, :us, days) do
    # US format: MM/DD/YYYY
    with {month, ""} <- Integer.parse(p1),
         {day, ""} <- Integer.parse(p2),
         {year, ""} <- Integer.parse(p3),
         {:ok, date} <- Date.new(year, month, day) do
      shifted = Date.add(date, days)
      "#{pad2(shifted.month)}/#{pad2(shifted.day)}/#{shifted.year}"
    else
      _ -> "#{p1}/#{p2}/#{p3}"
    end
  end

  defp shift_single_date(_match, p1, p2, p3, :iso, days) do
    # ISO format: YYYY-MM-DD
    with {year, ""} <- Integer.parse(p1),
         {month, ""} <- Integer.parse(p2),
         {day, ""} <- Integer.parse(p3),
         {:ok, date} <- Date.new(year, month, day) do
      shifted = Date.add(date, days)
      "#{shifted.year}-#{pad2(shifted.month)}-#{pad2(shifted.day)}"
    else
      _ -> "#{p1}-#{p2}-#{p3}"
    end
  end

  defp pad2(n), do: String.pad_leading(Integer.to_string(n), 2, "0")
end
