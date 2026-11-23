defmodule MedlumLlm.CVL.Stages.NLIPairGeneratorTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.Stages.NLIPairGenerator

  describe "process/1" do
    test "generates NLI pairs from claims" do
      sample = make_sample(%{
        source_document: "Patient has type 2 diabetes.",
        error_type: :incorrect,
        claims: [
          %{text: "Patient has type 1 diabetes", type: :diagnosis}
        ]
      })

      assert {:ok, result} = NLIPairGenerator.process(sample)
      assert length(result.data.nli_pairs) == 1

      pair = hd(result.data.nli_pairs)
      assert pair.premise =~ "type 2 diabetes"
      assert pair.hypothesis =~ "type 1 diabetes"
      assert pair.label == :contradiction
    end

    test "maps :incorrect error to :contradiction label" do
      sample = make_sample(%{
        source_document: "Test premise",
        error_type: :incorrect,
        claims: [%{text: "Test hypothesis", type: :general}]
      })

      assert {:ok, result} = NLIPairGenerator.process(sample)
      assert hd(result.data.nli_pairs).label == :contradiction
    end

    test "maps :error to :neutral label" do
      sample = make_sample(%{
        source_document: "Test premise",
        error_type: :error,
        claims: [%{text: "Test hypothesis", type: :general}]
      })

      assert {:ok, result} = NLIPairGenerator.process(sample)
      assert hd(result.data.nli_pairs).label == :neutral
    end

    test "maps :low_confidence to :neutral label" do
      sample = make_sample(%{
        source_document: "Test premise",
        error_type: :low_confidence,
        claims: [%{text: "Test hypothesis", type: :general}]
      })

      assert {:ok, result} = NLIPairGenerator.process(sample)
      assert hd(result.data.nli_pairs).label == :neutral
    end

    test "uses question and options as premise when source_document is missing" do
      sample = make_sample(%{
        question: "What is the diagnosis?",
        options: %{"A" => "Diabetes", "B" => "Hypertension"},
        error_type: :incorrect,
        claims: [%{text: "The diagnosis is diabetes", type: :diagnosis}]
      })

      assert {:ok, result} = NLIPairGenerator.process(sample)
      pair = hd(result.data.nli_pairs)

      assert pair.premise =~ "What is the diagnosis?"
      assert pair.premise =~ "Options:"
    end

    test "skips samples without valid NLI pairs" do
      sample = make_sample(%{
        source_document: "Test",
        error_type: :incorrect,
        claims: []
      })

      assert {:skip, :no_valid_pairs} = NLIPairGenerator.process(sample)
    end

    test "includes claim type in NLI pair" do
      sample = make_sample(%{
        source_document: "Test premise",
        error_type: :incorrect,
        claims: [%{text: "Patient takes metformin", type: :medication}]
      })

      assert {:ok, result} = NLIPairGenerator.process(sample)
      assert hd(result.data.nli_pairs).claim_type == :medication
    end

    test "includes metadata in NLI pair" do
      sample = make_sample(%{
        source_document: "Test premise",
        error_type: :incorrect,
        model: :test_model,
        benchmark: :test_bench,
        claims: [%{text: "Test hypothesis", type: :general, span: {0, 10}, index: 0}]
      })

      assert {:ok, result} = NLIPairGenerator.process(sample)
      metadata = hd(result.data.nli_pairs).metadata

      assert metadata.error_type == :incorrect
      assert metadata.model == :test_model
      assert metadata.benchmark == :test_bench
    end

    test "ensures hypothesis ends with punctuation" do
      sample = make_sample(%{
        source_document: "Test premise",
        error_type: :incorrect,
        claims: [%{text: "No ending punctuation", type: :general}]
      })

      assert {:ok, result} = NLIPairGenerator.process(sample)
      hypothesis = hd(result.data.nli_pairs).hypothesis

      assert String.ends_with?(hypothesis, ".")
    end

    test "capitalizes hypothesis first letter" do
      sample = make_sample(%{
        source_document: "Test premise",
        error_type: :incorrect,
        claims: [%{text: "lowercase start", type: :general}]
      })

      assert {:ok, result} = NLIPairGenerator.process(sample)
      hypothesis = hd(result.data.nli_pairs).hypothesis

      assert String.starts_with?(hypothesis, "L")
    end
  end

  describe "error_type_to_label/1" do
    test "maps all error types correctly" do
      assert NLIPairGenerator.error_type_to_label(:incorrect) == :contradiction
      assert NLIPairGenerator.error_type_to_label(:contradiction) == :contradiction
      assert NLIPairGenerator.error_type_to_label(:error) == :neutral
      assert NLIPairGenerator.error_type_to_label(:low_confidence) == :neutral
      assert NLIPairGenerator.error_type_to_label(:timeout) == :neutral
      assert NLIPairGenerator.error_type_to_label(:unknown) == :neutral
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
