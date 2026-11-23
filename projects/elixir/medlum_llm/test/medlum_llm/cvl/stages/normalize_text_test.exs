defmodule MedlumLlm.CVL.Stages.NormalizeTextTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.Stages.NormalizeText

  describe "process/1" do
    test "normalizes whitespace" do
      sample = make_sample(%{source_document: "Hello   World\r\n\r\nTest"})

      assert {:ok, result} = NormalizeText.process(sample)
      assert result.data.source_document == "Hello World\n\nTest"
    end

    test "normalizes smart quotes" do
      sample = make_sample(%{source_document: "\u201CHello\u201D \u2018World\u2019"})

      assert {:ok, result} = NormalizeText.process(sample)
      assert result.data.source_document == "\"Hello\" 'World'"
    end

    test "normalizes dashes" do
      sample = make_sample(%{source_document: "range: 10–20 mg"})

      assert {:ok, result} = NormalizeText.process(sample)
      assert result.data.source_document == "range: 10-20 mg"
    end

    test "removes zero-width characters" do
      sample = make_sample(%{source_document: "Hello\u200BWorld"})

      assert {:ok, result} = NormalizeText.process(sample)
      assert result.data.source_document == "HelloWorld"
    end

    test "trims whitespace from each line" do
      sample = make_sample(%{source_document: "  Hello  \n  World  "})

      assert {:ok, result} = NormalizeText.process(sample)
      assert result.data.source_document == "Hello\nWorld"
    end

    test "collapses multiple blank lines" do
      sample = make_sample(%{source_document: "Hello\n\n\n\nWorld"})

      assert {:ok, result} = NormalizeText.process(sample)
      assert result.data.source_document == "Hello\n\nWorld"
    end

    test "handles nil fields gracefully" do
      sample = make_sample(%{source_document: "Hello", generated_summary: nil})

      assert {:ok, result} = NormalizeText.process(sample)
      assert result.data.source_document == "Hello"
      assert result.data.generated_summary == nil
    end

    test "normalizes all text fields" do
      sample = make_sample(%{
        source_document: "Doc  text",
        generated_summary: "Summary  text",
        question: "Question  text",
        gold_answer: "Gold  answer",
        predicted_answer: "Predicted  answer"
      })

      assert {:ok, result} = NormalizeText.process(sample)
      assert result.data.source_document == "Doc text"
      assert result.data.generated_summary == "Summary text"
      assert result.data.question == "Question text"
      assert result.data.gold_answer == "Gold answer"
      assert result.data.predicted_answer == "Predicted answer"
    end

    test "preserves non-string values" do
      sample = make_sample(%{
        source_document: "Hello",
        numeric_field: 123,
        list_field: ["a", "b"]
      })

      assert {:ok, result} = NormalizeText.process(sample)
      assert result.data.numeric_field == 123
      assert result.data.list_field == ["a", "b"]
    end
  end

  describe "behaviour callbacks" do
    test "async? returns false" do
      assert NormalizeText.async?() == false
    end

    test "concurrency returns 1" do
      assert NormalizeText.concurrency() == 1
    end

    test "timeout returns 5000" do
      assert NormalizeText.timeout() == 5_000
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
