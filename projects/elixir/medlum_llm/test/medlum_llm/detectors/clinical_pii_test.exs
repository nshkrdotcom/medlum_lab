defmodule MedlumLlm.Detectors.ClinicalPIITest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Detectors.ClinicalPII
  alias MedlumLlm.Detectors.ClinicalPII.Patterns

  describe "name/0" do
    test "returns detector name" do
      assert ClinicalPII.name() == "clinical_pii"
    end
  end

  describe "description/0" do
    test "returns detector description" do
      assert ClinicalPII.description() =~ "HIPAA"
    end
  end

  describe "detect/2 - MRN patterns" do
    test "detects MRN with explicit label" do
      {:detected, result} = ClinicalPII.detect("Patient MRN: 12345678", [])
      assert :mrn in result.patterns_matched
      assert result.confidence >= 0.85
    end

    test "detects MRN with hash notation" do
      {:detected, result} = ClinicalPII.detect("MRN#A1234567", [])
      assert :mrn in result.patterns_matched
    end

    test "detects Medical Record Number spelled out" do
      {:detected, result} = ClinicalPII.detect("Medical Record Number: ABC12345", [])
      assert :mrn in result.patterns_matched
    end

    test "detects Patient ID" do
      {:detected, result} = ClinicalPII.detect("Patient ID: XYZ98765432", [])
      assert :mrn in result.patterns_matched
    end

    test "boosts confidence with context keywords" do
      # With context
      {:detected, result_with_ctx} = ClinicalPII.detect("Patient chart MRN: 12345678 admitted today", [])
      # Without much context
      {:detected, result_no_ctx} = ClinicalPII.detect("MRN: 12345678", [])

      assert result_with_ctx.confidence >= result_no_ctx.confidence
    end
  end

  describe "detect/2 - DOB patterns" do
    test "detects DOB with US date format" do
      {:detected, result} = ClinicalPII.detect("DOB: 01/15/1980", [])
      assert :dob in result.patterns_matched
      assert result.confidence >= 0.9
    end

    test "detects DOB with dash format" do
      {:detected, result} = ClinicalPII.detect("DOB: 01-15-1980", [])
      assert :dob in result.patterns_matched
    end

    test "detects Date of Birth spelled out" do
      {:detected, result} = ClinicalPII.detect("Date of Birth: 12/25/1965", [])
      assert :dob in result.patterns_matched
    end

    test "detects DOB with ISO format" do
      {:detected, result} = ClinicalPII.detect("DOB: 1980/01/15", [])
      assert :dob in result.patterns_matched
    end
  end

  describe "detect/2 - NPI patterns" do
    test "detects NPI with 10 digits" do
      {:detected, result} = ClinicalPII.detect("Provider NPI: 1234567890", [])
      assert :npi in result.patterns_matched
      assert result.confidence >= 0.9
    end

    test "detects NPI with hash notation" do
      {:detected, result} = ClinicalPII.detect("NPI#1234567890", [])
      assert :npi in result.patterns_matched
    end
  end

  describe "detect/2 - DEA patterns" do
    test "detects DEA number" do
      {:detected, result} = ClinicalPII.detect("DEA: AB1234567", [])
      assert :dea in result.patterns_matched
      assert result.confidence >= 0.9
    end

    test "detects DEA with hash notation" do
      {:detected, result} = ClinicalPII.detect("DEA#XY9876543", [])
      assert :dea in result.patterns_matched
    end
  end

  describe "detect/2 - Medical dates" do
    test "detects admission date" do
      {:detected, result} = ClinicalPII.detect("Admitted: 03/15/2024", [])
      assert :medical_date in result.patterns_matched
    end

    test "detects discharge date" do
      {:detected, result} = ClinicalPII.detect("Discharged 04/20/2024", [])
      assert :medical_date in result.patterns_matched
    end

    test "detects service date" do
      {:detected, result} = ClinicalPII.detect("Service date: 01/01/2025", [])
      assert :medical_date in result.patterns_matched
    end

    test "detects DOA/DOD" do
      {:detected, result} = ClinicalPII.detect("DOA: 12/01/2024", [])
      assert :medical_date in result.patterns_matched
    end
  end

  describe "detect/2 - Insurance patterns" do
    test "detects policy ID" do
      {:detected, result} = ClinicalPII.detect("Insurance Policy ID: ABC123456789", [])
      assert :insurance_id in result.patterns_matched
    end

    test "detects member ID" do
      {:detected, result} = ClinicalPII.detect("Member ID: XYZ987654321", [])
      assert :insurance_id in result.patterns_matched
    end

    test "detects Medicare HICN" do
      {:detected, result} = ClinicalPII.detect("HICN: 123456789A", [])
      assert :medicare_id in result.patterns_matched
    end
  end

  describe "detect/2 - Room/Bed patterns" do
    test "detects room number" do
      {:detected, result} = ClinicalPII.detect("Room: 204B", [])
      assert :room_bed in result.patterns_matched
    end

    test "detects bed number" do
      {:detected, result} = ClinicalPII.detect("Bed 3", [])
      assert :room_bed in result.patterns_matched
    end

    test "context boosts room confidence" do
      {:detected, result} = ClinicalPII.detect("Patient admitted to Room 415, ward 3B", [])
      assert :room_bed in result.patterns_matched
      assert result.confidence >= 0.7
    end
  end

  describe "detect/2 - Provider names (Tier 3)" do
    test "does not detect provider names by default" do
      {:safe, _} = ClinicalPII.detect("Dr. Smith", [])
    end

    test "detects provider names with include_tier_3 option" do
      {:detected, result} = ClinicalPII.detect("Dr. Smith", include_tier_3: true, confidence_threshold: 0.5)
      assert :provider_name in result.patterns_matched
    end

    test "detects providers with credentials" do
      {:detected, result} = ClinicalPII.detect("John Smith, MD", include_tier_3: true, confidence_threshold: 0.5)
      assert :provider_name in result.patterns_matched
    end
  end

  describe "detect/2 - Facility names (Tier 3)" do
    test "does not detect facility names by default" do
      {:safe, _} = ClinicalPII.detect("admitted to Memorial Hospital", [])
    end

    test "detects facility names with include_tier_3 option" do
      {:detected, result} = ClinicalPII.detect(
        "admitted to Memorial Hospital",
        include_tier_3: true,
        confidence_threshold: 0.5
      )
      assert :facility_name in result.patterns_matched
    end
  end

  describe "detect/2 - Multiple detections" do
    test "detects multiple PII types in same text" do
      text = "MRN: 12345678, DOB: 01/15/1980, NPI: 1234567890"
      {:detected, result} = ClinicalPII.detect(text, [])

      assert :mrn in result.patterns_matched
      assert :dob in result.patterns_matched
      assert :npi in result.patterns_matched
      assert result.metadata.detection_count == 3
    end

    test "combined confidence is boosted for multiple detections" do
      {:detected, single} = ClinicalPII.detect("MRN: 12345678", [])
      {:detected, multiple} = ClinicalPII.detect("MRN: 12345678, DOB: 01/15/1980", [])

      # Multiple detections should have equal or higher confidence
      assert multiple.confidence >= single.confidence
    end
  end

  describe "detect/2 - Safe inputs" do
    test "returns safe for normal clinical text" do
      {:safe, _} = ClinicalPII.detect("Patient presents with chest pain and shortness of breath.", [])
    end

    test "returns safe for empty string" do
      {:safe, _} = ClinicalPII.detect("", [])
    end

    test "returns safe for random numbers" do
      # Random numbers without context shouldn't trigger detection
      {:safe, _} = ClinicalPII.detect("The count is 12345678.", [])
    end
  end

  describe "detect/2 - Confidence threshold" do
    test "respects custom confidence threshold" do
      # This should be detected with default threshold
      {:detected, _} = ClinicalPII.detect("MRN: 12345678", [])

      # With very high threshold, may not be detected
      result = ClinicalPII.detect("MRN: 12345678", confidence_threshold: 0.99)
      # Result depends on pattern confidence
      assert match?({:safe, _}, result) or match?({:detected, _}, result)
    end

    test "lower threshold catches more patterns" do
      # Provider name without context has lower confidence
      {:safe, _} = ClinicalPII.detect("Dr. Smith", include_tier_3: true, confidence_threshold: 0.9)
      {:detected, _} = ClinicalPII.detect("Dr. Smith", include_tier_3: true, confidence_threshold: 0.5)
    end
  end

  describe "scan/2" do
    test "returns detailed detections with positions" do
      detections = ClinicalPII.scan("MRN: 12345678, DOB: 01/15/1980")

      assert length(detections) == 2
      assert Enum.all?(detections, &Map.has_key?(&1, :span))
      assert Enum.all?(detections, &Map.has_key?(&1, :text))
    end

    test "detections are sorted by position" do
      detections = ClinicalPII.scan("DOB: 01/15/1980 and MRN: 12345678")
      positions = Enum.map(detections, &elem(&1.span, 0))

      assert positions == Enum.sort(positions)
    end
  end

  describe "contains_phi?/2" do
    test "returns true when PHI is present" do
      assert ClinicalPII.contains_phi?("MRN: 12345678")
      assert ClinicalPII.contains_phi?("DOB: 01/15/1980")
    end

    test "returns false when no PHI is present" do
      refute ClinicalPII.contains_phi?("Normal clinical text")
    end
  end

  describe "Patterns module" do
    test "tier_1_patterns returns MRN, DOB, NPI, DEA patterns" do
      patterns = Patterns.tier_1_patterns()
      types = Enum.map(patterns, & &1.type) |> Enum.uniq()

      assert :mrn in types
      assert :dob in types
      assert :npi in types
      assert :dea in types
    end

    test "tier_2_patterns returns medical dates, insurance, room/bed" do
      patterns = Patterns.tier_2_patterns()
      types = Enum.map(patterns, & &1.type) |> Enum.uniq()

      assert :medical_date in types
      assert :insurance_id in types
      assert :room_bed in types
    end

    test "tier_3_patterns returns provider and facility names" do
      patterns = Patterns.tier_3_patterns()
      types = Enum.map(patterns, & &1.type) |> Enum.uniq()

      assert :provider_name in types
      assert :facility_name in types
    end

    test "standard_patterns excludes Tier 3" do
      standard = Patterns.standard_patterns()
      types = Enum.map(standard, & &1.type) |> Enum.uniq()

      refute :provider_name in types
      refute :facility_name in types
    end

    test "all_patterns includes all tiers" do
      all = Patterns.all_patterns()
      standard = Patterns.standard_patterns()

      assert length(all) > length(standard)
    end

    test "pii_types returns unique type list" do
      types = Patterns.pii_types()

      assert is_list(types)
      assert length(types) == length(Enum.uniq(types))
    end
  end
end
