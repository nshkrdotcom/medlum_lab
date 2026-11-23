defmodule MedlumLlm.CVL.ClaimExtractorTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.ClaimExtractor

  describe "extract/1 with bullet points" do
    test "extracts claims from dash bullets" do
      summary = """
      - Started metformin 500mg twice daily
      - HbA1c is 7.2%
      - Diagnosed with type 2 diabetes
      """

      claims = ClaimExtractor.extract(summary)

      assert length(claims) == 3
      assert Enum.at(claims, 0).text == "Started metformin 500mg twice daily"
      assert Enum.at(claims, 1).text == "HbA1c is 7.2%"
      assert Enum.at(claims, 2).text == "Diagnosed with type 2 diabetes"
    end

    test "extracts claims from asterisk bullets" do
      summary = """
      * Patient has chest pain
      * ECG shows ST elevation
      * Started on heparin
      """

      claims = ClaimExtractor.extract(summary)

      assert length(claims) == 3
      assert Enum.at(claims, 0).text == "Patient has chest pain"
    end

    test "extracts claims from unicode bullet points" do
      summary = """
      • Lisinopril 10mg daily
      • Blood pressure 140/90
      """

      claims = ClaimExtractor.extract(summary)

      assert length(claims) == 2
      assert Enum.at(claims, 0).text == "Lisinopril 10mg daily"
    end

    test "handles mixed indentation" do
      summary = """
        - First claim
        - Second claim
      """

      claims = ClaimExtractor.extract(summary)

      assert length(claims) == 2
    end
  end

  describe "extract/1 with numbered items" do
    test "extracts claims from numbered list with periods" do
      summary = """
      1. Patient admitted with chest pain
      2. Troponin elevated at 0.5
      3. Started on aspirin 325mg
      """

      claims = ClaimExtractor.extract(summary)

      assert length(claims) == 3
      assert Enum.at(claims, 0).text == "Patient admitted with chest pain"
      assert Enum.at(claims, 1).text == "Troponin elevated at 0.5"
      assert Enum.at(claims, 2).text == "Started on aspirin 325mg"
    end

    test "extracts claims from numbered list with parentheses" do
      summary = """
      1) Diagnosis: Type 2 diabetes
      2) Treatment: Metformin 500mg BID
      """

      claims = ClaimExtractor.extract(summary)

      assert length(claims) == 2
      assert Enum.at(claims, 0).text == "Diagnosis: Type 2 diabetes"
    end
  end

  describe "extract/1 with sentences" do
    test "splits by sentence boundaries when no structural markers" do
      summary = "Patient has diabetes. HbA1c is 7.2%. Started on metformin."

      claims = ClaimExtractor.extract(summary)

      assert length(claims) == 3
      assert Enum.at(claims, 0).text == "Patient has diabetes."
      assert Enum.at(claims, 1).text == "HbA1c is 7.2%."
      assert Enum.at(claims, 2).text == "Started on metformin."
    end

    test "does not split on decimal points" do
      summary = "The value is 7.2 percent. This is significant."

      claims = ClaimExtractor.extract(summary)

      # Should split into 2 sentences, not break on 7.2
      assert length(claims) == 2
      assert Enum.at(claims, 0).text == "The value is 7.2 percent."
    end

    test "handles single sentence" do
      summary = "Patient has type 2 diabetes"

      claims = ClaimExtractor.extract(summary)

      assert length(claims) == 1
      assert Enum.at(claims, 0).text == "Patient has type 2 diabetes"
    end
  end

  describe "extract/1 with options" do
    test "filters by minimum length" do
      summary = """
      - A
      - Valid claim here
      - B
      """

      claims = ClaimExtractor.extract(summary, min_length: 5)

      assert length(claims) == 1
      assert hd(claims).text == "Valid claim here"
    end

    test "filters by maximum length" do
      summary = """
      - Short
      - This is a very long claim that exceeds the maximum length limit
      """

      claims = ClaimExtractor.extract(summary, min_length: 1, max_length: 20)

      assert length(claims) == 1
      assert hd(claims).text == "Short"
    end
  end

  describe "extract/1 claim IDs" do
    test "assigns sequential IDs" do
      summary = """
      - First claim
      - Second claim
      - Third claim
      """

      claims = ClaimExtractor.extract(summary)

      assert Enum.at(claims, 0).id == "c1"
      assert Enum.at(claims, 1).id == "c2"
      assert Enum.at(claims, 2).id == "c3"
    end
  end

  describe "extract/1 source tracking" do
    test "includes source offset information" do
      summary = "- First claim"

      claims = ClaimExtractor.extract(summary)

      claim = hd(claims)
      assert is_integer(claim.source_offset) or is_nil(claim.source_offset)
      assert is_integer(claim.source_length)
    end
  end

  describe "extract_texts/1" do
    test "returns only text strings" do
      summary = """
      - Claim one
      - Claim two
      """

      texts = ClaimExtractor.extract_texts(summary)

      assert texts == ["Claim one", "Claim two"]
    end
  end

  describe "edge cases" do
    test "handles empty string" do
      claims = ClaimExtractor.extract("")

      assert claims == []
    end

    test "handles whitespace only" do
      claims = ClaimExtractor.extract("   \n\n  ")

      assert claims == []
    end

    test "normalizes internal whitespace" do
      summary = "- Claim   with   extra   spaces"

      claims = ClaimExtractor.extract(summary)

      assert hd(claims).text == "Claim with extra spaces"
    end

    test "handles claims with special characters" do
      summary = "- HbA1c: 7.2% (elevated)"

      claims = ClaimExtractor.extract(summary)

      assert hd(claims).text == "HbA1c: 7.2% (elevated)"
    end
  end
end
