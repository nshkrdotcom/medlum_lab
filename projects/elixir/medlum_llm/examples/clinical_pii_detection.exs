# Clinical PII Detection Example
#
# Run with: mix run examples/clinical_pii_detection.exs

alias MedlumLlm.Detectors.ClinicalPII
alias MedlumLlm.Detectors.ClinicalPII.Patterns

IO.puts("=== Clinical PII Detection Examples ===\n")

# Example clinical text with various PHI
clinical_note = """
Patient: John Smith
MRN: 12345678
DOB: 01/15/1980
NPI: 1234567890

Chief Complaint: Chest pain

History: The patient was admitted on 03/15/2024 with complaints of chest pain.
Attending physician: Dr. Jane Doe, MD
Room: 204B

Insurance: Policy ID ABC123456789

Assessment: Acute coronary syndrome
Plan: Cardiac catheterization scheduled for 03/16/2024
"""

IO.puts("Input Text:")
IO.puts("---")
IO.puts(clinical_note)
IO.puts("---\n")

# Detect with standard settings (Tier 1 + Tier 2)
IO.puts("1. Standard Detection (Tier 1 + Tier 2):")
case ClinicalPII.detect(clinical_note) do
  {:detected, result} ->
    IO.puts("   Status: PHI Detected")
    IO.puts("   Confidence: #{Float.round(result.confidence, 2)}")
    IO.puts("   Types: #{inspect(result.patterns_matched)}")
    IO.puts("   Count: #{result.metadata.detection_count}")

  {:safe, _} ->
    IO.puts("   Status: Safe (no PHI detected)")
end

IO.puts("")

# Detect with Tier 3 (includes names and facilities)
IO.puts("2. Aggressive Detection (All Tiers):")
case ClinicalPII.detect(clinical_note, include_tier_3: true, confidence_threshold: 0.5) do
  {:detected, result} ->
    IO.puts("   Status: PHI Detected")
    IO.puts("   Confidence: #{Float.round(result.confidence, 2)}")
    IO.puts("   Types: #{inspect(result.patterns_matched)}")
    IO.puts("   Count: #{result.metadata.detection_count}")

  {:safe, _} ->
    IO.puts("   Status: Safe")
end

IO.puts("")

# Scan for detailed positions
IO.puts("3. Detailed Scan (with positions):")
detections = ClinicalPII.scan(clinical_note, include_tier_3: true, confidence_threshold: 0.5)
for detection <- detections do
  {start, stop} = detection.span
  IO.puts("   - Type: #{detection.type}")
  IO.puts("     Text: \"#{detection.text}\"")
  IO.puts("     Position: #{start}-#{stop}")
  IO.puts("     Confidence: #{Float.round(detection.confidence, 2)}")
  IO.puts("")
end

# Quick check
IO.puts("4. Quick PHI Check:")
IO.puts("   Contains PHI? #{ClinicalPII.contains_phi?(clinical_note)}")

IO.puts("")

# Pattern information
IO.puts("5. Available Pattern Types:")
IO.puts("   Tier 1 types: #{Patterns.tier_1_patterns() |> Enum.map(& &1.type) |> Enum.uniq() |> inspect()}")
IO.puts("   Tier 2 types: #{Patterns.tier_2_patterns() |> Enum.map(& &1.type) |> Enum.uniq() |> inspect()}")
IO.puts("   Tier 3 types: #{Patterns.tier_3_patterns() |> Enum.map(& &1.type) |> Enum.uniq() |> inspect()}")
IO.puts("   Total patterns: #{length(Patterns.all_patterns())}")

IO.puts("\n=== Done ===")
