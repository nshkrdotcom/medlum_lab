# HIPAA Redaction Example
#
# Run with: mix run examples/hipaa_redaction.exs

alias MedlumLlm.Guardrails
alias MedlumLlm.Guardrails.Redactor
alias MedlumLlm.Guardrails.Audit

IO.puts("=== HIPAA Redaction Examples ===\n")

# Example clinical text
clinical_note = """
Patient: John Smith, 95-year-old male
MRN: 12345678
DOB: 01/15/1928

Chief Complaint: Shortness of breath

The patient was admitted to Memorial Hospital on 03/15/2024.
Attending: Dr. Jane Doe, MD (NPI: 1234567890, DEA: AB1234567)
Room: 204B

Insurance: Policy ID ABC123456789, HICN: 123456789A

Assessment: COPD exacerbation
Discharged: 03/20/2024
"""

IO.puts("Original Text:")
IO.puts("---")
IO.puts(clinical_note)
IO.puts("---\n")

# 1. Basic redaction with placeholders
IO.puts("1. Basic Redaction (Placeholder):")
redacted = Redactor.redact(clinical_note)
IO.puts(redacted)
IO.puts("")

# 2. Aggressive mode with Tier 3
IO.puts("2. Aggressive Redaction (includes names/facilities):")
aggressive = Redactor.redact(clinical_note, mode: :aggressive)
IO.puts(aggressive)
IO.puts("")

# 3. Hash-based redaction
IO.puts("3. Hash-Based Redaction (deterministic):")
hashed = Redactor.redact(clinical_note,
  replacement_style: :hash,
  seed: "study_001"
)
IO.puts(hashed)
IO.puts("")

# 4. Same seed produces same output
IO.puts("4. Deterministic Verification:")
hashed2 = Redactor.redact(clinical_note,
  replacement_style: :hash,
  seed: "study_001"
)
IO.puts("   Same output with same seed? #{hashed == hashed2}")
IO.puts("")

# 5. Redaction with manifest
IO.puts("5. Redaction with Audit Manifest:")
{redacted_text, manifest} = Redactor.redact_with_manifest(clinical_note, mode: :aggressive)
IO.puts("   Redaction count: #{manifest.redaction_count}")
IO.puts("   Types found: #{inspect(Map.keys(manifest.redaction_types))}")
IO.puts("   Type counts: #{inspect(manifest.redaction_types)}")
IO.puts("   Mode: #{manifest.mode}")
IO.puts("   Original hash: #{String.slice(manifest.original_hash, 0, 16)}...")
IO.puts("   Redacted hash: #{String.slice(manifest.redacted_hash, 0, 16)}...")
IO.puts("")

# 6. Age binning
IO.puts("6. Age Binning (HIPAA Safe Harbor):")
IO.puts("   bin_age(45) = #{Redactor.bin_age(45)}")
IO.puts("   bin_age(89) = #{Redactor.bin_age(89)}")
IO.puts("   bin_age(90) = #{Redactor.bin_age(90)}")
IO.puts("   bin_age(95) = #{Redactor.bin_age(95)}")
IO.puts("")

age_text = "Patient is a 95-year-old male with 85-year-old spouse"
IO.puts("   Original: \"#{age_text}\"")
IO.puts("   Binned:   \"#{Redactor.bin_ages_in_text(age_text)}\"")
IO.puts("")

# 7. Date shifting
IO.puts("7. Date Shifting (preserves intervals):")
date_text = "Admitted: 03/15/2024, Surgery: 03/18/2024, Discharged: 03/20/2024"
shifted = Redactor.shift_dates(date_text, 45)
IO.puts("   Original: \"#{date_text}\"")
IO.puts("   Shifted:  \"#{shifted}\"")
IO.puts("   (Shifted by 45 days, intervals preserved)")
IO.puts("")

# 8. Full pipeline with audit
IO.puts("8. Full De-identification Pipeline:")
full_deidentified =
  clinical_note
  |> Redactor.bin_ages_in_text()
  |> Redactor.shift_dates(30)
  |> Redactor.redact(mode: :aggressive, replacement_style: :hash, seed: "export_001")

IO.puts(full_deidentified)
IO.puts("")

# 9. Audit logging
IO.puts("9. Audit Logging:")
{_, manifest} = Redactor.redact_with_manifest(clinical_note)
{:ok, entry} = Audit.log_redaction(manifest, "user_123", "session_abc")
IO.puts("   Logged operation: #{entry.operation}")
IO.puts("   Operator: #{entry.operator_id}")
IO.puts("   Session: #{entry.session_id}")
IO.puts("   Types redacted: #{inspect(entry.redaction_types)}")
IO.puts("   Count: #{entry.redaction_count}")
IO.puts("")

# 10. Using Guardrails module
IO.puts("10. Using Guardrails.validate_output:")
llm_response = "The patient MRN: 12345678 was treated for DOB: 01/15/1980 symptoms."
case Guardrails.validate_output(llm_response) do
  {:ok, safe_text, manifest} ->
    IO.puts("    Input:    \"#{llm_response}\"")
    IO.puts("    Redacted: \"#{safe_text}\"")
    IO.puts("    Redactions: #{manifest.redaction_count}")

  {:ok, text} ->
    IO.puts("    No PHI detected")
    IO.puts("    Output: \"#{text}\"")
end

IO.puts("\n=== Done ===")
