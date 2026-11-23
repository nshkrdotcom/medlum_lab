defmodule MedlumLlm.PII.ClinicalTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.PII.Clinical

  describe "patterns/0" do
    test "returns non-empty list of patterns" do
      patterns = Clinical.patterns()

      assert is_list(patterns)
      assert length(patterns) > 0
    end

    test "all patterns are valid {regex, replacement} tuples" do
      Enum.each(Clinical.patterns(), fn {regex, replacement} ->
        assert is_struct(regex, Regex), "Expected regex pattern"
        assert is_binary(replacement), "Expected string replacement"
      end)
    end
  end

  describe "aggressive_patterns/0" do
    test "includes more patterns than standard patterns" do
      standard = Clinical.patterns()
      aggressive = Clinical.aggressive_patterns()

      assert length(aggressive) > length(standard)
    end

    test "includes all standard patterns" do
      standard = Clinical.patterns()
      aggressive = Clinical.aggressive_patterns()

      aggressive_sources = Enum.map(aggressive, fn {regex, _rep} -> Regex.source(regex) end)

      Enum.each(standard, fn {regex, _rep} ->
        assert Regex.source(regex) in aggressive_sources,
               "Standard pattern #{Regex.source(regex)} should be in aggressive set"
      end)
    end
  end

  describe "redact/2 - MRN detection" do
    test "redacts MRN with explicit label" do
      assert Clinical.redact("MRN: 12345678") == "[MRN_REDACTED]"
      assert Clinical.redact("MRN#12345678") == "[MRN_REDACTED]"
      assert Clinical.redact("MRN 12345678") == "[MRN_REDACTED]"
    end

    test "redacts medical record number" do
      assert Clinical.redact("medical record 12345678") == "[MRN_REDACTED]"
      assert Clinical.redact("medical record number: 12345678") == "[MRN_REDACTED]"
    end

    test "redacts chart number" do
      assert Clinical.redact("chart 12345678") == "[MRN_REDACTED]"
      assert Clinical.redact("Chart #12345678") == "[MRN_REDACTED]"
    end

    test "redacts patient ID" do
      assert Clinical.redact("Patient ID: ABC12345") == "[MRN_REDACTED]"
      assert Clinical.redact("Pt ID 12345678") == "[MRN_REDACTED]"
      assert Clinical.redact("Acct: 123456789") == "[MRN_REDACTED]"
    end

    test "preserves text without MRN" do
      assert Clinical.redact("No MRN here") == "No MRN here"
    end
  end

  describe "redact/2 - DOB detection" do
    test "redacts DOB with explicit label" do
      assert Clinical.redact("DOB: 01/15/1980") == "[DOB_REDACTED]"
      assert Clinical.redact("DOB 12-25-1990") == "[DOB_REDACTED]"
      assert Clinical.redact("DOB:1/1/80") == "[DOB_REDACTED]"
    end

    test "redacts date of birth spelled out" do
      assert Clinical.redact("date of birth: 01/15/1980") == "[DOB_REDACTED]"
      assert Clinical.redact("birthdate 12/25/1990") == "[DOB_REDACTED]"
    end

    test "redacts DOB in ISO format" do
      assert Clinical.redact("DOB: 1980-01-15") == "[DOB_REDACTED]"
    end

    test "preserves text without DOB" do
      assert Clinical.redact("Patient was born healthy") == "Patient was born healthy"
    end
  end

  describe "redact/2 - NPI detection" do
    test "redacts NPI with explicit label" do
      assert Clinical.redact("NPI: 1234567890") == "[NPI_REDACTED]"
      assert Clinical.redact("NPI#1234567890") == "[NPI_REDACTED]"
      assert Clinical.redact("NPI 1234567890") == "[NPI_REDACTED]"
    end

    test "does not redact shorter numbers as NPI" do
      # NPI requires exactly 10 digits
      assert Clinical.redact("NPI: 123456789") == "NPI: 123456789"
    end

    test "preserves text without NPI" do
      assert Clinical.redact("No NPI provided") == "No NPI provided"
    end
  end

  describe "redact/2 - DEA detection" do
    test "redacts DEA number with explicit label" do
      assert Clinical.redact("DEA: AB1234567") == "[DEA_REDACTED]"
      assert Clinical.redact("DEA#CD9876543") == "[DEA_REDACTED]"
      assert Clinical.redact("DEA XY1234567") == "[DEA_REDACTED]"
    end

    test "does not redact invalid DEA format" do
      # DEA requires 2 letters + 7 digits
      assert Clinical.redact("DEA: 1234567") == "DEA: 1234567"
      assert Clinical.redact("DEA: ABC12345") == "DEA: ABC12345"
    end
  end

  describe "redact/2 - Medicare/Medicaid detection" do
    test "redacts Medicare HICN" do
      assert Clinical.redact("HIC: 123456789A") == "[MEDICARE_REDACTED]"
      assert Clinical.redact("HICN 123456789A1") == "[MEDICARE_REDACTED]"
      assert Clinical.redact("Medicare ID: 123456789A") == "[MEDICARE_REDACTED]"
    end

    test "redacts Medicare MBI (new format)" do
      # MBI format: 1 digit, 1 letter, 2 alphanumeric, 3 alphanumeric, 4 alphanumeric
      assert Clinical.redact("MBI: 1AB2CD3EF4G") == "[MEDICARE_REDACTED]"
    end

    test "redacts Medicaid ID" do
      assert Clinical.redact("Medicaid: 12345678ABC") == "[MEDICAID_REDACTED]"
      assert Clinical.redact("Medicaid ID 123456789") == "[MEDICAID_REDACTED]"
    end
  end

  describe "redact/2 - Insurance ID detection" do
    test "redacts policy ID" do
      assert Clinical.redact("Policy ID: ABC12345678") == "[INSURANCE_REDACTED]"
      assert Clinical.redact("policy number ABC12345678") == "[INSURANCE_REDACTED]"
    end

    test "redacts member ID" do
      assert Clinical.redact("Member ID: XYZ987654321") == "[INSURANCE_REDACTED]"
      assert Clinical.redact("member# ABC12345678") == "[INSURANCE_REDACTED]"
    end

    test "redacts subscriber ID" do
      assert Clinical.redact("Subscriber ID: 12345678") == "[INSURANCE_REDACTED]"
    end

    test "redacts group ID" do
      assert Clinical.redact("Group ID: 123456") == "[INSURANCE_REDACTED]"
      assert Clinical.redact("Group number 1234567") == "[INSURANCE_REDACTED]"
    end
  end

  describe "redact/2 - Medical date detection" do
    test "redacts admission date" do
      assert Clinical.redact("Admitted: 01/15/2025") == "[DATE_REDACTED]"
      assert Clinical.redact("Admission date: 01/15/2025") == "[DATE_REDACTED]"
      assert Clinical.redact("admit 1/15/25") == "[DATE_REDACTED]"
    end

    test "redacts discharge date" do
      assert Clinical.redact("Discharged: 01/20/2025") == "[DATE_REDACTED]"
      assert Clinical.redact("discharge date 01-20-2025") == "[DATE_REDACTED]"
    end

    test "redacts service/visit date" do
      assert Clinical.redact("Service date: 01/15/2025") == "[DATE_REDACTED]"
      assert Clinical.redact("Visit 01/15/2025") == "[DATE_REDACTED]"
      assert Clinical.redact("Encounter date: 01/15/2025") == "[DATE_REDACTED]"
    end

    test "redacts DOA/DOD abbreviations" do
      assert Clinical.redact("DOA: 01/15/2025") == "[DATE_REDACTED]"
      assert Clinical.redact("DOD 01/20/2025") == "[DATE_REDACTED]"
    end

    test "redacts procedure/surgery date" do
      assert Clinical.redact("Procedure date: 01/15/2025") == "[DATE_REDACTED]"
      assert Clinical.redact("Surgery 01/15/2025") == "[DATE_REDACTED]"
    end
  end

  describe "redact/2 - Room/Bed detection" do
    test "redacts room number" do
      assert Clinical.redact("Room 412") == "[ROOM_REDACTED]"
      assert Clinical.redact("Rm. 412A") == "[ROOM_REDACTED]"
      assert Clinical.redact("room #100") == "[ROOM_REDACTED]"
    end

    test "redacts bed number" do
      assert Clinical.redact("Bed 2") == "[ROOM_REDACTED]"
      assert Clinical.redact("bed# 3A") == "[ROOM_REDACTED]"
    end

    test "redacts unit designation" do
      assert Clinical.redact("Unit 5") == "[ROOM_REDACTED]"
      assert Clinical.redact("unit# 12A") == "[ROOM_REDACTED]"
    end
  end

  describe "redact/2 with :aggressive mode - Provider names" do
    test "redacts Dr. prefix names" do
      assert Clinical.redact("Dr. Smith", :aggressive) == "[PROVIDER_REDACTED]"
      assert Clinical.redact("Dr Smith", :aggressive) == "[PROVIDER_REDACTED]"
      assert Clinical.redact("Dr. John Smith", :aggressive) == "[PROVIDER_REDACTED]"
    end

    test "redacts names with credentials" do
      assert Clinical.redact("John Smith, MD", :aggressive) == "[PROVIDER_REDACTED]"
      assert Clinical.redact("Jane Doe DO", :aggressive) == "[PROVIDER_REDACTED]"
      assert Clinical.redact("Mary Johnson NP", :aggressive) == "[PROVIDER_REDACTED]"
    end

    test "redacts names with explicit roles" do
      assert Clinical.redact("Attending physician: John Smith", :aggressive) ==
               "[PROVIDER_REDACTED]"

      assert Clinical.redact("Referring doctor: Jane Doe", :aggressive) == "[PROVIDER_REDACTED]"
    end

    test "does not redact provider names in standard mode" do
      assert Clinical.redact("Dr. Smith", :standard) == "Dr. Smith"
    end
  end

  describe "redact/2 with :aggressive mode - Facility names" do
    test "redacts hospital names" do
      assert Clinical.redact("Mercy Hospital", :aggressive) == "[FACILITY_REDACTED]"
      assert Clinical.redact("General Medical Center", :aggressive) == "[FACILITY_REDACTED]"
    end

    test "redacts clinic names" do
      assert Clinical.redact("Downtown Clinic", :aggressive) == "[FACILITY_REDACTED]"
    end

    test "redacts health system names" do
      assert Clinical.redact("Memorial Health System", :aggressive) == "[FACILITY_REDACTED]"
    end

    test "redacts St./Saint prefixed facilities" do
      assert Clinical.redact("St. Mary's Hospital", :aggressive) == "[FACILITY_REDACTED]"
      assert Clinical.redact("Saint Joseph Medical", :aggressive) == "[FACILITY_REDACTED]"
    end

    test "does not redact facility names in standard mode" do
      assert Clinical.redact("Mercy Hospital", :standard) == "Mercy Hospital"
    end
  end

  describe "redact/2 with :aggressive mode - Addresses" do
    test "redacts street addresses" do
      assert Clinical.redact("123 Main St", :aggressive) == "[ADDRESS_REDACTED]"
      assert Clinical.redact("456 Oak Avenue", :aggressive) == "[ADDRESS_REDACTED]"
      assert Clinical.redact("789 Pine Road", :aggressive) == "[ADDRESS_REDACTED]"
      assert Clinical.redact("100 Elm Blvd", :aggressive) == "[ADDRESS_REDACTED]"
    end

    test "does not redact addresses in standard mode" do
      assert Clinical.redact("123 Main St", :standard) == "123 Main St"
    end
  end

  describe "redact/2 - Multiple PII in text" do
    test "redacts multiple PII types" do
      text = "Patient MRN: 12345678, DOB: 01/15/1980, NPI: 1234567890"

      result = Clinical.redact(text)

      assert result ==
               "Patient [MRN_REDACTED], [DOB_REDACTED], [NPI_REDACTED]"
    end

    test "preserves non-PII text around redactions" do
      text = "The patient with MRN: 12345678 was seen today."

      result = Clinical.redact(text)

      assert result == "The patient with [MRN_REDACTED] was seen today."
    end
  end

  describe "detect/1" do
    test "detects MRN" do
      assert :mrn in Clinical.detect("MRN: 12345678")
      assert :mrn in Clinical.detect("Patient ID: ABC12345")
    end

    test "detects DOB" do
      assert :dob in Clinical.detect("DOB: 01/15/1980")
      assert :dob in Clinical.detect("date of birth: 01/15/1980")
    end

    test "detects NPI" do
      assert :npi in Clinical.detect("NPI: 1234567890")
    end

    test "detects DEA" do
      assert :dea in Clinical.detect("DEA: AB1234567")
    end

    test "detects Medicare" do
      assert :medicare in Clinical.detect("Medicare: 123456789A1")
    end

    test "detects Medicaid" do
      assert :medicaid in Clinical.detect("Medicaid: 12345678ABC")
    end

    test "detects insurance ID" do
      assert :insurance_id in Clinical.detect("Policy ID: ABC12345678")
    end

    test "detects medical dates" do
      assert :medical_date in Clinical.detect("Admitted: 01/15/2025")
    end

    test "detects room/bed" do
      assert :room_bed in Clinical.detect("Room 412")
    end

    test "detects provider names" do
      assert :provider_name in Clinical.detect("Dr. Smith ordered labs")
      assert :provider_name in Clinical.detect("John Doe, MD")
    end

    test "detects facility names" do
      assert :facility_name in Clinical.detect("Mercy Hospital")
    end

    test "detects addresses" do
      assert :address in Clinical.detect("123 Main St")
    end

    test "returns empty list for clean text" do
      assert Clinical.detect("No PII in this clinical note.") == []
    end

    test "detects multiple PII types" do
      text = "MRN: 12345678, DOB: 01/15/1980"
      result = Clinical.detect(text)

      assert :mrn in result
      assert :dob in result
    end

    test "handles non-string input" do
      assert Clinical.detect(nil) == []
      assert Clinical.detect(123) == []
    end
  end

  describe "pii_types/0" do
    test "returns list of all clinical PII types" do
      types = Clinical.pii_types()

      assert is_list(types)
      assert :mrn in types
      assert :dob in types
      assert :npi in types
      assert :dea in types
      assert :medicare in types
      assert :medicaid in types
      assert :insurance_id in types
      assert :medical_date in types
      assert :room_bed in types
      assert :provider_name in types
      assert :facility_name in types
      assert :address in types
    end
  end
end
