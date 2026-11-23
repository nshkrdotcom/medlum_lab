defmodule MedlumLlm.CVL.Stages.ClaimExtractionTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.Stages.ClaimExtraction

  describe "process/1" do
    test "extracts claims from source document" do
      sample = make_sample(%{
        source_document: "Patient takes metformin 500mg daily. Blood pressure is 120/80."
      })

      assert {:ok, result} = ClaimExtraction.process(sample)
      assert length(result.data.claims) >= 2
    end

    test "categorizes medication claims" do
      sample = make_sample(%{
        source_document: "Patient takes lisinopril 10mg daily for hypertension."
      })

      assert {:ok, result} = ClaimExtraction.process(sample)

      medication_claims = Enum.filter(result.data.claims, &(&1.type == :medication))
      assert length(medication_claims) >= 1
    end

    test "categorizes lab value claims" do
      sample = make_sample(%{
        source_document: "Hemoglobin level is 14.2 g/dL. Creatinine was 1.1 mg/dL."
      })

      assert {:ok, result} = ClaimExtraction.process(sample)

      lab_claims = Enum.filter(result.data.claims, &(&1.type == :lab_value))
      assert length(lab_claims) >= 1
    end

    test "categorizes diagnosis claims" do
      sample = make_sample(%{
        source_document: "Patient was diagnosed with type 2 diabetes mellitus."
      })

      assert {:ok, result} = ClaimExtraction.process(sample)

      diagnosis_claims = Enum.filter(result.data.claims, &(&1.type == :diagnosis))
      assert length(diagnosis_claims) >= 1
    end

    test "categorizes temporal claims" do
      sample = make_sample(%{
        source_document: "Symptoms started 3 weeks ago. Follow-up scheduled in 2 months."
      })

      assert {:ok, result} = ClaimExtraction.process(sample)

      temporal_claims = Enum.filter(result.data.claims, &(&1.type == :temporal))
      assert length(temporal_claims) >= 1
    end

    test "extracts claims from both source and generated text" do
      sample = make_sample(%{
        source_document: "Patient has diabetes.",
        generated_summary: "The patient takes insulin."
      })

      assert {:ok, result} = ClaimExtraction.process(sample)
      assert length(result.data.source_claims) >= 1
      assert length(result.data.generated_claims) >= 1
    end

    test "handles bullet points" do
      sample = make_sample(%{
        source_document: """
        Medications:
        - Metformin 500mg
        - Lisinopril 10mg
        - Atorvastatin 20mg
        """
      })

      assert {:ok, result} = ClaimExtraction.process(sample)
      assert length(result.data.claims) >= 3
    end

    test "handles numbered lists" do
      sample = make_sample(%{
        source_document: """
        1. Patient has hypertension
        2. Blood pressure elevated
        3. Started medication
        """
      })

      assert {:ok, result} = ClaimExtraction.process(sample)
      assert length(result.data.claims) >= 3
    end

    test "filters out very short claims" do
      sample = make_sample(%{
        source_document: "OK. Yes. Patient takes metformin 500mg daily."
      })

      assert {:ok, result} = ClaimExtraction.process(sample)

      # "OK" and "Yes" should be filtered out
      texts = Enum.map(result.data.claims, & &1.text)
      refute "OK" in texts
      refute "Yes" in texts
    end

    test "handles empty documents" do
      sample = make_sample(%{source_document: "", generated_summary: ""})

      assert {:ok, result} = ClaimExtraction.process(sample)
      assert result.data.claims == []
    end

    test "includes span information" do
      sample = make_sample(%{
        source_document: "Patient takes metformin."
      })

      assert {:ok, result} = ClaimExtraction.process(sample)
      claim = hd(result.data.claims)
      assert claim.span != nil
    end
  end

  describe "extract_claims/1" do
    test "splits on sentence boundaries" do
      claims = ClaimExtraction.extract_claims("First sentence. Second sentence.")
      assert length(claims) == 2
    end

    test "handles abbreviations correctly" do
      claims = ClaimExtraction.extract_claims("Dr. Smith prescribed medication. The dose is 10mg.")
      # Should not split on "Dr."
      assert length(claims) == 2
    end

    test "splits on semicolons" do
      claims =
        ClaimExtraction.extract_claims(
          "Patient has diabetes; also has hypertension"
        )

      assert length(claims) == 2
    end
  end

  defp make_sample(data) do
    %Forge.Sample{
      id: "test_#{System.unique_integer()}",
      pipeline: :test,
      data: data,
      measurements: %{},
      status: :pending,
      created_at: DateTime.utc_now()
    }
  end
end
