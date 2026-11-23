defmodule MedlumLlm.CVL.Stages.PIIRedactionTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.Stages.PIIRedaction

  describe "process/1" do
    test "redacts MRN from source document" do
      sample = make_sample(%{
        source_document: "Patient MRN: 12345678"
      })

      assert {:ok, result} = PIIRedaction.process(sample)
      refute result.data.source_document =~ "12345678"
      assert result.data.source_document =~ "[MRN_REDACTED]"
    end

    test "redacts dates" do
      sample = make_sample(%{
        source_document: "DOB: 01/15/1980"
      })

      assert {:ok, result} = PIIRedaction.process(sample)
      refute result.data.source_document =~ "01/15/1980"
    end

    test "redacts all text fields" do
      sample = make_sample(%{
        source_document: "MRN: 12345678",
        generated_summary: "MRN: 87654321",
        question: "Patient MRN: 11111111"
      })

      assert {:ok, result} = PIIRedaction.process(sample)
      refute result.data.source_document =~ "12345678"
      refute result.data.generated_summary =~ "87654321"
      refute result.data.question =~ "11111111"
    end

    test "redacts NLI pairs premise and hypothesis" do
      sample = make_sample(%{
        source_document: "Test",
        nli_pairs: [
          %{
            premise: "Patient MRN: 12345678",
            hypothesis: "MRN is 87654321"
          }
        ]
      })

      assert {:ok, result} = PIIRedaction.process(sample)
      pair = hd(result.data.nli_pairs)

      refute pair.premise =~ "12345678"
      refute pair.hypothesis =~ "87654321"
    end

    test "redacts claims text" do
      sample = make_sample(%{
        source_document: "Test",
        claims: [
          %{text: "Patient MRN: 12345678", type: :general}
        ]
      })

      assert {:ok, result} = PIIRedaction.process(sample)
      claim = hd(result.data.claims)

      refute claim.text =~ "12345678"
    end

    test "generates audit manifest" do
      sample = make_sample(%{
        source_document: "Patient MRN: 12345678"
      })

      assert {:ok, result} = PIIRedaction.process(sample, audit: true)
      assert result.data.redaction_manifests != nil
    end

    test "preserves medical terminology" do
      sample = make_sample(%{
        source_document: "Patient takes metformin 500mg for type 2 diabetes."
      })

      assert {:ok, result} = PIIRedaction.process(sample)
      assert result.data.source_document =~ "metformin"
      assert result.data.source_document =~ "500mg"
      assert result.data.source_document =~ "diabetes"
    end

    test "handles nil fields" do
      sample = make_sample(%{
        source_document: "Test",
        generated_summary: nil
      })

      assert {:ok, result} = PIIRedaction.process(sample)
      assert result.data.generated_summary == nil
    end

    test "accepts mode option" do
      sample = make_sample(%{
        source_document: "Patient John Smith, MRN: 12345678"
      })

      # Aggressive mode should redact more
      assert {:ok, result} = PIIRedaction.process(sample, mode: :aggressive)
      refute result.data.source_document =~ "12345678"
    end
  end

  describe "behaviour callbacks" do
    test "async? returns false" do
      assert PIIRedaction.async?() == false
    end

    test "concurrency returns 1" do
      assert PIIRedaction.concurrency() == 1
    end

    test "timeout returns 30000" do
      assert PIIRedaction.timeout() == 30_000
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
