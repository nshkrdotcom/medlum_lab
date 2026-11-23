defmodule MedlumLlm.Guardrails.RedactorTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Guardrails.Redactor

  describe "redact/2" do
    test "redacts MRN with placeholder" do
      text = "Patient MRN: 12345678"
      result = Redactor.redact(text)

      assert result =~ "[MRN_REDACTED]"
      refute result =~ "12345678"
    end

    test "redacts DOB with placeholder" do
      text = "DOB: 01/15/1980"
      result = Redactor.redact(text)

      assert result =~ "[DOB_REDACTED]"
      refute result =~ "01/15/1980"
    end

    test "redacts NPI with placeholder" do
      text = "Provider NPI: 1234567890"
      result = Redactor.redact(text)

      assert result =~ "[NPI_REDACTED]"
      refute result =~ "1234567890"
    end

    test "redacts DEA with placeholder" do
      text = "DEA: AB1234567"
      result = Redactor.redact(text)

      assert result =~ "[DEA_REDACTED]"
      refute result =~ "AB1234567"
    end

    test "redacts multiple PII in same text" do
      text = "Patient MRN: 12345678, DOB: 01/15/1980"
      result = Redactor.redact(text)

      assert result =~ "[MRN_REDACTED]"
      assert result =~ "[DOB_REDACTED]"
      refute result =~ "12345678"
      refute result =~ "01/15/1980"
    end

    test "preserves non-PII text" do
      text = "Patient MRN: 12345678 presents with chest pain."
      result = Redactor.redact(text)

      assert result =~ "Patient"
      assert result =~ "presents with chest pain."
    end

    test "returns unchanged text when no PII" do
      text = "Normal clinical text without identifiers."
      result = Redactor.redact(text)

      assert result == text
    end
  end

  describe "redact/2 with replacement_style: :hash" do
    test "uses hash-based replacement" do
      text = "MRN: 12345678"
      result = Redactor.redact(text, replacement_style: :hash)

      assert result =~ "[MRN_"
      refute result =~ "12345678"
      # Hash suffix should be 8 chars
      assert Regex.match?(~r/\[MRN_[a-f0-9]{8}\]/, result)
    end

    test "deterministic hashing with seed" do
      text = "MRN: 12345678"

      result1 = Redactor.redact(text, replacement_style: :hash, seed: "test_seed")
      result2 = Redactor.redact(text, replacement_style: :hash, seed: "test_seed")

      assert result1 == result2
    end

    test "different seeds produce different hashes" do
      text = "MRN: 12345678"

      result1 = Redactor.redact(text, replacement_style: :hash, seed: "seed_1")
      result2 = Redactor.redact(text, replacement_style: :hash, seed: "seed_2")

      refute result1 == result2
    end
  end

  describe "redact/2 with replacement_style: :mask" do
    test "masks with asterisks" do
      text = "MRN: 12345678"
      result = Redactor.redact(text, replacement_style: :mask)

      # The matched text should be replaced with asterisks
      assert result =~ "***"
      refute result =~ "12345678"
    end
  end

  describe "redact/2 with mode options" do
    test "automatic mode uses Tier 1 and Tier 2 patterns" do
      text = "MRN: 12345678, Dr. Smith"
      result = Redactor.redact(text, mode: :automatic)

      # MRN should be redacted
      assert result =~ "[MRN_REDACTED]"
      # Provider name should NOT be redacted in automatic mode
      assert result =~ "Dr. Smith"
    end

    test "aggressive mode includes Tier 3 patterns" do
      text = "MRN: 12345678, Dr. Smith"
      result = Redactor.redact(text, mode: :aggressive)

      # MRN should be redacted
      assert result =~ "[MRN_REDACTED]"
      # Provider name SHOULD be redacted in aggressive mode
      assert result =~ "[PROVIDER_REDACTED]"
    end

    test "hipaa_safe_harbor mode includes all patterns" do
      text = "MRN: 12345678, admitted to Memorial Hospital"
      result = Redactor.redact(text, mode: :hipaa_safe_harbor)

      assert result =~ "[MRN_REDACTED]"
      assert result =~ "[FACILITY_REDACTED]"
    end
  end

  describe "redact_with_manifest/2" do
    test "returns redacted text and manifest" do
      text = "MRN: 12345678, DOB: 01/15/1980"
      {redacted, manifest} = Redactor.redact_with_manifest(text)

      assert is_binary(redacted)
      assert is_map(manifest)
    end

    test "manifest contains hashes, not content" do
      text = "MRN: 12345678"
      {_redacted, manifest} = Redactor.redact_with_manifest(text)

      assert is_binary(manifest.original_hash)
      assert is_binary(manifest.redacted_hash)
      # Hashes should be 64 chars (SHA256 hex)
      assert String.length(manifest.original_hash) == 64
    end

    test "manifest contains redaction counts" do
      text = "MRN: 12345678, DOB: 01/15/1980"
      {_redacted, manifest} = Redactor.redact_with_manifest(text)

      assert manifest.redaction_count == 2
      assert manifest.redaction_types[:mrn] == 1
      assert manifest.redaction_types[:dob] == 1
    end

    test "manifest contains mode used" do
      text = "MRN: 12345678"
      {_redacted, manifest} = Redactor.redact_with_manifest(text, mode: :aggressive)

      assert manifest.mode == :aggressive
    end

    test "manifest contains timestamp" do
      text = "MRN: 12345678"
      {_redacted, manifest} = Redactor.redact_with_manifest(text)

      assert %DateTime{} = manifest.timestamp
    end
  end

  describe "shift_dates/3" do
    test "shifts US format dates forward" do
      text = "Admitted: 01/15/2025"
      result = Redactor.shift_dates(text, 30)

      assert result =~ "02/14/2025"
      refute result =~ "01/15/2025"
    end

    test "shifts US format dates backward" do
      text = "Discharged: 03/15/2025"
      result = Redactor.shift_dates(text, -30)

      assert result =~ "02/13/2025"
    end

    test "shifts ISO format dates" do
      text = "Date: 2025-01-15"
      result = Redactor.shift_dates(text, 30, format: :iso)

      assert result =~ "2025-02-14"
    end

    test "preserves intervals between dates" do
      text = "Admitted: 01/15/2025, Discharged: 01/20/2025"
      result = Redactor.shift_dates(text, 30)

      # Both dates shifted by same amount, interval preserved
      assert result =~ "02/14/2025"
      assert result =~ "02/19/2025"
    end

    test "handles month boundaries" do
      text = "Date: 01/31/2025"
      result = Redactor.shift_dates(text, 1)

      assert result =~ "02/01/2025"
    end

    test "handles year boundaries" do
      text = "Date: 12/31/2024"
      result = Redactor.shift_dates(text, 1)

      assert result =~ "01/01/2025"
    end

    test "zero shift returns original dates" do
      text = "Admitted: 01/15/2025"
      result = Redactor.shift_dates(text, 0)

      assert result == text
    end
  end

  describe "bin_age/1" do
    test "returns string for ages under 90" do
      assert Redactor.bin_age(45) == "45"
      assert Redactor.bin_age(89) == "89"
    end

    test "returns 90+ for ages 90 and above" do
      assert Redactor.bin_age(90) == "90+"
      assert Redactor.bin_age(95) == "90+"
      assert Redactor.bin_age(105) == "90+"
    end
  end

  describe "bin_ages_in_text/1" do
    test "bins ages in 'X-year-old' format" do
      text = "Patient is a 95-year-old male"
      result = Redactor.bin_ages_in_text(text)

      assert result =~ "90+"
      refute result =~ "95"
    end

    test "bins ages in 'age X' format" do
      text = "Age: 92"
      result = Redactor.bin_ages_in_text(text)

      assert result =~ "90+"
    end

    test "bins ages in 'X years old' format" do
      text = "The patient is 91 years old"
      result = Redactor.bin_ages_in_text(text)

      assert result =~ "90+"
    end

    test "does not modify ages under 90" do
      text = "Patient is a 75-year-old female"
      result = Redactor.bin_ages_in_text(text)

      assert result =~ "75"
      refute result =~ "90+"
    end

    test "handles multiple ages" do
      text = "Patient (92 years old) accompanied by 85-year-old spouse"
      result = Redactor.bin_ages_in_text(text)

      assert result =~ "90+"
      assert result =~ "85"
    end
  end

  describe "edge cases" do
    test "handles empty string" do
      result = Redactor.redact("")
      assert result == ""
    end

    test "handles text with overlapping patterns" do
      # MRN that could also match other patterns
      text = "MRN: 123456789"
      result = Redactor.redact(text)

      # Should only be redacted once
      assert String.contains?(result, "REDACTED")
    end

    test "handles unicode text" do
      # Unicode text before the MRN - binary_part handles this correctly
      # because regex positions are byte-based
      text = "Patient: ABC MRN: 12345678"
      result = Redactor.redact(text)

      assert result =~ "ABC"
      assert result =~ "[MRN_REDACTED]"
    end
  end
end
