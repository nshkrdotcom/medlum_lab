# Redaction Guide

This guide covers the redaction capabilities in MedlumLlm for de-identifying clinical text.

## Overview

The `MedlumLlm.Guardrails.Redactor` module provides multiple strategies for removing Protected Health Information (PHI) from clinical documents while preserving document utility for clinical workflows and research.

## Redaction Modes

### Automatic Mode (Default)

Uses Tier 1 and Tier 2 patterns for balanced precision and recall:

```elixir
text = "Patient MRN: 12345678, DOB: 01/15/1980"

MedlumLlm.Guardrails.Redactor.redact(text, mode: :automatic)
# => "Patient [MRN_REDACTED], [DOB_REDACTED]"
```

Detects:
- MRN, Patient ID
- Date of Birth
- NPI, DEA numbers
- Medical dates (admission, discharge, service)
- Insurance IDs, Medicare IDs
- Room/bed numbers

### Aggressive Mode

Includes Tier 3 patterns (names, facilities) with lower confidence threshold:

```elixir
text = "Dr. Smith at Memorial Hospital treated MRN: 12345678"

MedlumLlm.Guardrails.Redactor.redact(text, mode: :aggressive)
# => "[PROVIDER_REDACTED] at [FACILITY_REDACTED] treated [MRN_REDACTED]"
```

Use for:
- Training data export
- Research publications
- Data sharing

### HIPAA Safe Harbor Mode

Most comprehensive detection, covering all 18 HIPAA identifiers:

```elixir
MedlumLlm.Guardrails.Redactor.redact(text, mode: :hipaa_safe_harbor)
```

## Replacement Styles

### Placeholder (Default)

Type-specific placeholders:

```elixir
MedlumLlm.Guardrails.Redactor.redact(text, replacement_style: :placeholder)
# "MRN: 12345678" => "MRN: [MRN_REDACTED]"
# "DOB: 01/15/1980" => "DOB: [DOB_REDACTED]"
# "Dr. Smith" => "Dr. [PROVIDER_REDACTED]"
```

Placeholder templates:
- `[MRN_REDACTED]`
- `[DOB_REDACTED]`
- `[NPI_REDACTED]`
- `[DEA_REDACTED]`
- `[MEDICARE_REDACTED]`
- `[INSURANCE_REDACTED]`
- `[DATE_REDACTED]`
- `[ROOM_REDACTED]`
- `[PROVIDER_REDACTED]`
- `[FACILITY_REDACTED]`

### Hash-Based

Deterministic pseudonymization for research:

```elixir
MedlumLlm.Guardrails.Redactor.redact(text,
  replacement_style: :hash,
  seed: "study_001"
)
# "MRN: 12345678" => "MRN: [MRN_a1b2c3d4]"
```

Benefits:
- Same input + seed = same output (reproducible)
- Same entity maps to same pseudonym within document
- 8-character hex suffix

### Mask

Simple asterisk replacement:

```elixir
MedlumLlm.Guardrails.Redactor.redact(text, replacement_style: :mask)
# "MRN: 12345678" => "MRN: **************"
```

## Deterministic Redaction

For reproducible research, use seeded hashing:

```elixir
text = "Patient MRN: 12345678"

# Same seed produces same output
result1 = Redactor.redact(text, replacement_style: :hash, seed: "study_001")
result2 = Redactor.redact(text, replacement_style: :hash, seed: "study_001")

result1 == result2  # true

# Different seed produces different output
result3 = Redactor.redact(text, replacement_style: :hash, seed: "study_002")
result1 != result3  # true
```

Use cases:
- Reproducible de-identification pipelines
- Cross-document entity linking (same patient ID → same pseudonym)
- Re-running exports with identical results

## Date Handling

### Date Shifting

Shift dates while preserving temporal intervals:

```elixir
text = "Admitted: 01/15/2025, Surgery: 01/18/2025, Discharged: 01/20/2025"

MedlumLlm.Guardrails.Redactor.shift_dates(text, 30)
# => "Admitted: 02/14/2025, Surgery: 02/17/2025, Discharged: 02/19/2025"

# Intervals preserved:
# Admission to Surgery: 3 days
# Surgery to Discharge: 2 days
```

Options:
- Positive days: shift forward
- Negative days: shift backward
- Zero: no change

Supported formats:
- US: `MM/DD/YYYY`, `MM-DD-YYYY`
- ISO: `YYYY-MM-DD`, `YYYY/MM/DD`

```elixir
# Specify format hint for better accuracy
Redactor.shift_dates(text, 30, format: :us)
Redactor.shift_dates(text, 30, format: :iso)
Redactor.shift_dates(text, 30, format: :auto)  # default
```

### Age Binning

Per HIPAA Safe Harbor, ages >89 become "90+":

```elixir
# Single age
Redactor.bin_age(45)   # => "45"
Redactor.bin_age(89)   # => "89"
Redactor.bin_age(90)   # => "90+"
Redactor.bin_age(105)  # => "90+"

# Ages in text
text = "Patient is a 95-year-old male with 85-year-old spouse"
Redactor.bin_ages_in_text(text)
# => "Patient is a 90+-year-old male with 85-year-old spouse"
```

Recognized patterns:
- `X-year-old`
- `X years old`
- `age X`
- `X yo` / `X y.o.`

## Redaction with Manifest

Get audit information along with redacted text:

```elixir
text = "MRN: 12345678, DOB: 01/15/1980, NPI: 1234567890"

{redacted, manifest} = Redactor.redact_with_manifest(text)

manifest
# => %{
#   original_hash: "abc123...",   # SHA256 of input
#   redacted_hash: "def456...",   # SHA256 of output
#   mode: :automatic,
#   redaction_types: %{mrn: 1, dob: 1, npi: 1},
#   redaction_count: 3,
#   timestamp: ~U[2025-01-25 12:00:00Z]
# }
```

Manifest contains:
- Hashes (not content) for verification
- Counts by type for reporting
- Timestamp for audit trail
- Mode used

## Combining Techniques

For comprehensive de-identification:

```elixir
text = """
Patient: John Smith, 92-year-old male
MRN: 12345678
DOB: 01/15/1932
Admitted: 03/15/2024
Attending: Dr. Jane Doe, MD
"""

# 1. Bin ages
text = Redactor.bin_ages_in_text(text)

# 2. Shift dates
text = Redactor.shift_dates(text, 45)

# 3. Redact identifiers
{redacted, manifest} = Redactor.redact_with_manifest(text,
  mode: :aggressive,
  replacement_style: :hash,
  seed: "export_001"
)
```

## Integration with Guardrails

Use the high-level API for validation + redaction:

```elixir
# Automatic redaction through validate_output
{:ok, safe_text, manifest} = MedlumLlm.Guardrails.validate_output(
  llm_response,
  config: MedlumLlm.Guardrails.export_config(seed: "study_001")
)

# Or use the pipeline
{:ok, safe_response} = MedlumLlm.Guardrails.pipeline(
  user_input,
  fn input -> MedlumLlm.Chat.generate(input) end
)
```

## Examples

### Clinical Summary Export

```elixir
defmodule MyApp.ExportPipeline do
  alias MedlumLlm.Guardrails.Redactor

  def export_summary(summary, opts \\ []) do
    seed = Keyword.get(opts, :seed, generate_seed())
    shift_days = Keyword.get(opts, :shift_days, :rand.uniform(365))

    summary
    |> Redactor.bin_ages_in_text()
    |> Redactor.shift_dates(shift_days)
    |> Redactor.redact(mode: :aggressive, replacement_style: :hash, seed: seed)
  end

  defp generate_seed, do: "export_#{Date.utc_today()}"
end
```

### Batch Processing

```elixir
documents
|> Task.async_stream(fn doc ->
  {redacted, manifest} = Redactor.redact_with_manifest(doc.text,
    mode: :hipaa_safe_harbor,
    seed: "batch_001"
  )
  %{doc | text: redacted, manifest: manifest}
end)
|> Enum.map(fn {:ok, doc} -> doc end)
```

### Research Data Pipeline

```elixir
defmodule Research.DataPipeline do
  alias MedlumLlm.Guardrails.{Redactor, Audit}

  def process_record(record, operator_id) do
    # De-identify
    {redacted, manifest} = Redactor.redact_with_manifest(
      record.text,
      mode: :aggressive,
      replacement_style: :hash,
      seed: record.study_id
    )

    # Audit log
    {:ok, _entry} = Audit.log_redaction(manifest, operator_id, record.session_id)

    # Return de-identified record
    %{record | text: redacted, phi_removed: true}
  end
end
```

## Performance Considerations

- Pattern matching is optimized for speed (<10ms typical)
- Use `mode: :automatic` for real-time applications
- Use `mode: :aggressive` only when higher recall is needed
- Hash calculation adds minimal overhead
- Batch processing benefits from Task.async_stream

## Limitations

1. **Pattern-based**: Novel identifier formats may be missed
2. **No semantic understanding**: Cannot detect PHI through context alone
3. **Name detection**: Higher false positive rate, use with confidence threshold tuning
4. **Date shifting**: Cannot handle malformed dates
5. **Institution-specific formats**: May need pattern customization
