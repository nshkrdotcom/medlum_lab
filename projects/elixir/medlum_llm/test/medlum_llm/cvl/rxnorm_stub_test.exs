defmodule MedlumLlm.CVL.RxNormStubTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.RxNormStub

  describe "lookup/1" do
    test "finds known medication" do
      assert {:ok, "6809"} = RxNormStub.lookup("metformin")
      assert {:ok, "6809"} = RxNormStub.lookup("Metformin")
    end

    test "returns error for unknown medication" do
      assert {:error, :not_found} = RxNormStub.lookup("fakemedicine")
    end

    test "is case insensitive" do
      assert {:ok, "29046"} = RxNormStub.lookup("LISINOPRIL")
      assert {:ok, "29046"} = RxNormStub.lookup("Lisinopril")
      assert {:ok, "29046"} = RxNormStub.lookup("lisinopril")
    end

    test "finds all supported medications" do
      medications = [
        {"metformin", "6809"},
        {"lisinopril", "29046"},
        {"aspirin", "1191"},
        {"atorvastatin", "83367"},
        {"omeprazole", "7646"},
        {"amlodipine", "17767"},
        {"warfarin", "11289"},
        {"insulin", "5856"}
      ]

      for {name, rxcui} <- medications do
        assert {:ok, ^rxcui} = RxNormStub.lookup(name)
      end
    end
  end

  describe "therapeutic_range/1" do
    test "returns range for medication with data" do
      {:ok, range} = RxNormStub.therapeutic_range("6809")
      assert range.min == 500
      assert range.max == 2550
      assert range.unit == "mg"
    end

    test "returns no_range_data for insulin" do
      assert {:error, :no_range_data} = RxNormStub.therapeutic_range("5856")
    end

    test "returns no_range_data for unknown rxcui" do
      assert {:error, :no_range_data} = RxNormStub.therapeutic_range("999999")
    end

    test "returns correct range for lisinopril" do
      {:ok, range} = RxNormStub.therapeutic_range("29046")
      assert range.min == 2.5
      assert range.max == 40
      assert range.unit == "mg"
    end
  end

  describe "typical_frequencies/1" do
    test "returns frequencies for metformin" do
      {:ok, freqs} = RxNormStub.typical_frequencies("6809")
      assert "daily" in freqs
      assert "twice_daily" in freqs
      assert "three_times_daily" in freqs
    end

    test "returns daily only for lisinopril" do
      {:ok, freqs} = RxNormStub.typical_frequencies("29046")
      assert freqs == ["daily"]
    end

    test "returns no_frequency_data for unknown rxcui" do
      assert {:error, :no_frequency_data} = RxNormStub.typical_frequencies("999999")
    end
  end

  describe "check_interactions/2" do
    test "finds known interaction" do
      {:ok, interactions} = RxNormStub.check_interactions("aspirin", ["warfarin"])
      assert "warfarin" in interactions
    end

    test "returns empty for no interactions" do
      {:ok, interactions} = RxNormStub.check_interactions("metformin", ["aspirin"])
      assert interactions == []
    end

    test "is case insensitive" do
      {:ok, interactions} = RxNormStub.check_interactions("ASPIRIN", ["WARFARIN"])
      assert "warfarin" in interactions
    end

    test "finds multiple interactions" do
      {:ok, interactions} = RxNormStub.check_interactions("aspirin", ["warfarin", "ibuprofen"])
      assert length(interactions) == 2
      assert "warfarin" in interactions
      assert "ibuprofen" in interactions
    end

    test "returns no_interaction_data for unknown drug" do
      assert {:error, :no_interaction_data} =
               RxNormStub.check_interactions("fakemedicine", ["aspirin"])
    end

    test "lisinopril interacts with potassium" do
      {:ok, interactions} = RxNormStub.check_interactions("lisinopril", ["potassium"])
      assert "potassium" in interactions
    end
  end

  describe "check_contraindications/2" do
    test "finds contraindication" do
      {:ok, contras} = RxNormStub.check_contraindications("metformin", ["renal failure"])
      assert "renal_failure" in contras
    end

    test "normalizes condition names with spaces" do
      {:ok, contras} = RxNormStub.check_contraindications("metformin", ["liver disease"])
      assert "liver_disease" in contras
    end

    test "returns empty for no contraindications" do
      {:ok, contras} = RxNormStub.check_contraindications("metformin", ["diabetes"])
      assert contras == []
    end

    test "is case insensitive" do
      {:ok, contras} = RxNormStub.check_contraindications("METFORMIN", ["RENAL_FAILURE"])
      assert "renal_failure" in contras
    end

    test "returns no_contraindication_data for unknown drug" do
      assert {:error, :no_contraindication_data} =
               RxNormStub.check_contraindications("fakemedicine", ["diabetes"])
    end

    test "warfarin contraindicated in pregnancy" do
      {:ok, contras} = RxNormStub.check_contraindications("warfarin", ["pregnancy"])
      assert "pregnancy" in contras
    end

    test "aspirin contraindicated with GI ulcer" do
      {:ok, contras} = RxNormStub.check_contraindications("aspirin", ["gi ulcer"])
      assert "gi_ulcer" in contras
    end

    test "finds multiple contraindications" do
      {:ok, contras} =
        RxNormStub.check_contraindications("warfarin", ["bleeding disorder", "pregnancy"])

      assert length(contras) == 2
    end
  end
end
