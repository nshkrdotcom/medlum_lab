defmodule MedlumLlm.CVL.SampleLoaderTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.SampleLoader

  describe "transform_to_anvil_sample/2" do
    test "transforms Forge sample to Anvil format" do
      forge_sample = %{
        id: "forge_123",
        data: %{
          source_document: "Patient has diabetes",
          generated_summary: "Patient is healthy",
          error_type: :contradiction,
          model: "openbio_8b",
          benchmark: "medqa"
        }
      }

      anvil_sample = SampleLoader.transform_to_anvil_sample(forge_sample, "eval_run_1")

      assert String.starts_with?(anvil_sample.id, "cvl_")
      assert anvil_sample.premise == "Patient has diabetes"
      assert anvil_sample.hypothesis == "Patient is healthy"
      assert anvil_sample.metadata.source == :eval_failure
      assert anvil_sample.metadata.forge_sample_id == "forge_123"
      assert anvil_sample.metadata.eval_run_id == "eval_run_1"
      assert anvil_sample.metadata.model == "openbio_8b"
      assert anvil_sample.metadata.error_type == :contradiction
    end

    test "handles string keys in data" do
      forge_sample = %{
        id: "forge_456",
        data: %{
          "source_document" => "Patient has hypertension",
          "generated_summary" => "Blood pressure is normal",
          "error_type" => "contradiction"
        }
      }

      anvil_sample = SampleLoader.transform_to_anvil_sample(forge_sample, "eval_run_2")

      assert anvil_sample.premise == "Patient has hypertension"
      assert anvil_sample.hypothesis == "Blood pressure is normal"
    end

    test "handles alternative field names" do
      forge_sample = %{
        id: "forge_789",
        data: %{
          premise: "Original premise text",
          hypothesis: "Original hypothesis text",
          model: "meditron_7b"
        }
      }

      anvil_sample = SampleLoader.transform_to_anvil_sample(forge_sample, "eval_run_3")

      assert anvil_sample.premise == "Original premise text"
      assert anvil_sample.hypothesis == "Original hypothesis text"
    end

    test "handles missing fields gracefully" do
      forge_sample = %{
        id: "forge_minimal",
        data: %{}
      }

      anvil_sample = SampleLoader.transform_to_anvil_sample(forge_sample, "eval_run_4")

      assert anvil_sample.id |> String.starts_with?("cvl_")
      assert anvil_sample.premise == ""
      assert anvil_sample.hypothesis == ""
      assert anvil_sample.metadata.source == :eval_failure
    end
  end

  describe "create_sample/3" do
    test "creates sample from premise and hypothesis" do
      sample =
        SampleLoader.create_sample(
          "Patient has elevated A1C of 9.5",
          "Patient's diabetes is well controlled",
          error_type: :contradiction
        )

      assert String.starts_with?(sample.id, "cvl_")
      assert sample.premise == "Patient has elevated A1C of 9.5"
      assert sample.hypothesis == "Patient's diabetes is well controlled"
      assert sample.metadata.error_type == :contradiction
      assert sample.metadata.source == :manual
    end

    test "creates sample with custom metadata" do
      sample =
        SampleLoader.create_sample(
          "Premise text",
          "Hypothesis text",
          source: :benchmark,
          model: "test_model",
          claim_type: :medication
        )

      assert sample.metadata.source == :benchmark
      assert sample.metadata.model == "test_model"
      assert sample.metadata.claim_type == :medication
    end

    test "includes created_at timestamp" do
      sample = SampleLoader.create_sample("P", "H")

      assert %DateTime{} = sample.metadata.created_at
    end
  end

  describe "sample ID generation" do
    test "generates unique IDs" do
      sample1 = SampleLoader.create_sample("P1", "H1")
      sample2 = SampleLoader.create_sample("P2", "H2")

      assert sample1.id != sample2.id
    end

    test "IDs have correct prefix" do
      sample = SampleLoader.create_sample("P", "H")

      assert String.starts_with?(sample.id, "cvl_")
    end

    test "IDs have expected length" do
      sample = SampleLoader.create_sample("P", "H")

      # cvl_ (4) + 16 hex chars = 20 total
      assert String.length(sample.id) == 20
    end
  end
end
