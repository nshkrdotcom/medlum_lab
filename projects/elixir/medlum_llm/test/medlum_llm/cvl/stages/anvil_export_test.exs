defmodule MedlumLlm.CVL.Stages.AnvilExportTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.Stages.AnvilExport

  describe "should_export?/2" do
    test "returns :export for low confidence samples" do
      sample = make_sample_with_confidence(0.3)

      assert {:ok, :export} = AnvilExport.should_export?(sample, 0.5)
    end

    test "returns :skip for high confidence samples" do
      sample = make_sample_with_confidence(0.8)

      assert {:skip, :high_confidence} = AnvilExport.should_export?(sample, 0.5)
    end

    test "returns :skip when confidence equals threshold" do
      sample = make_sample_with_confidence(0.5)

      assert {:skip, :high_confidence} = AnvilExport.should_export?(sample, 0.5)
    end

    test "returns :skip when no NLI pairs" do
      sample = %Forge.Sample{
        id: "test",
        pipeline: :test,
        data: %{},
        measurements: %{confidence: %{score: 0.3}},
        status: :pending,
        created_at: DateTime.utc_now()
      }

      assert {:skip, :no_nli_pairs} = AnvilExport.should_export?(sample, 0.5)
    end
  end

  describe "format_for_anvil/2" do
    test "formats sample with all required fields" do
      sample = make_sample(%{
        source_document: "Test premise",
        error_type: :incorrect,
        model: :test_model,
        benchmark: :test_bench,
        nli_pairs: [
          %{
            premise: "Test premise",
            hypothesis: "Test hypothesis",
            claim_type: :medication
          }
        ],
        nli_label: :contradiction
      })

      formatted = AnvilExport.format_for_anvil(sample, true)

      assert formatted.sample_id == sample.id
      assert formatted.task_type == :nli_classification
      assert length(formatted.options) == 3
      assert formatted.body =~ "Test premise"
      assert formatted.body =~ "Test hypothesis"
    end

    test "includes title with claim type and error type" do
      sample = make_sample(%{
        error_type: :incorrect,
        nli_pairs: [%{claim_type: :medication}]
      })

      formatted = AnvilExport.format_for_anvil(sample, false)

      assert formatted.title =~ "medication"
      assert formatted.title =~ "incorrect"
    end

    test "includes measurements when requested" do
      sample = make_sample_with_measurements()

      formatted = AnvilExport.format_for_anvil(sample, true)

      assert formatted.metadata.measurements != %{}
    end

    test "excludes measurements when not requested" do
      sample = make_sample_with_measurements()

      formatted = AnvilExport.format_for_anvil(sample, false)

      assert formatted.metadata.measurements == %{}
    end

    test "includes auto_label in metadata" do
      sample = make_sample(%{
        nli_label: :contradiction,
        nli_pairs: [%{premise: "p", hypothesis: "h", claim_type: :general}]
      })

      formatted = AnvilExport.format_for_anvil(sample, false)

      assert formatted.metadata.auto_label == :contradiction
    end
  end

  describe "process/1" do
    test "skips high confidence samples" do
      sample = make_sample_with_confidence(0.9)

      assert {:ok, result} = AnvilExport.process(sample)
      # Sample passes through unchanged (no anvil_job_id added)
      refute Map.has_key?(result.data, :anvil_job_id)
    end

    test "skips samples without NLI pairs" do
      sample = make_sample_with_confidence(0.3)

      assert {:ok, result} = AnvilExport.process(sample)
      refute Map.has_key?(result.data, :anvil_job_id)
    end
  end

  describe "behaviour callbacks" do
    test "async? returns true" do
      assert AnvilExport.async?() == true
    end

    test "concurrency returns 4" do
      assert AnvilExport.concurrency() == 4
    end

    test "timeout returns 60000" do
      assert AnvilExport.timeout() == 60_000
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

  defp make_sample_with_confidence(score) do
    %Forge.Sample{
      id: "test_#{System.unique_integer()}",
      pipeline: :test,
      data: %{
        nli_pairs: [%{premise: "p", hypothesis: "h", claim_type: :general}]
      },
      measurements: %{confidence: %{score: score}},
      status: :pending,
      created_at: DateTime.utc_now()
    }
  end

  defp make_sample_with_measurements do
    %Forge.Sample{
      id: "test_#{System.unique_integer()}",
      pipeline: :test,
      data: %{
        nli_pairs: [%{premise: "p", hypothesis: "h", claim_type: :general}]
      },
      measurements: %{
        medication: %{verdict: :entailment},
        confidence: %{score: 0.8}
      },
      status: :pending,
      created_at: DateTime.utc_now()
    }
  end
end
