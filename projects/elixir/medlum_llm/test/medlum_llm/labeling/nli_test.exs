defmodule MedlumLlm.Labeling.NLITest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Labeling.NLI

  describe "verdict_to_label/1" do
    test "converts :entailment to ENTAILMENT" do
      assert NLI.verdict_to_label(:entailment) == "ENTAILMENT"
    end

    test "converts :contradiction to CONTRADICTION" do
      assert NLI.verdict_to_label(:contradiction) == "CONTRADICTION"
    end

    test "converts :neutral to NEUTRAL" do
      assert NLI.verdict_to_label(:neutral) == "NEUTRAL"
    end

    test "raises FunctionClauseError for invalid verdict" do
      assert_raise FunctionClauseError, fn ->
        NLI.verdict_to_label(:invalid)
      end
    end
  end

  describe "label_to_verdict/1" do
    test "parses ENTAILMENT to :entailment" do
      assert NLI.label_to_verdict("ENTAILMENT") == {:ok, :entailment}
    end

    test "parses CONTRADICTION to :contradiction" do
      assert NLI.label_to_verdict("CONTRADICTION") == {:ok, :contradiction}
    end

    test "parses NEUTRAL to :neutral" do
      assert NLI.label_to_verdict("NEUTRAL") == {:ok, :neutral}
    end

    test "returns error for lowercase labels" do
      assert NLI.label_to_verdict("entailment") == {:error, :invalid_label}
    end

    test "returns error for invalid labels" do
      assert NLI.label_to_verdict("INVALID") == {:error, :invalid_label}
    end

    test "returns error for non-string input" do
      assert NLI.label_to_verdict(:entailment) == {:error, :invalid_label}
      assert NLI.label_to_verdict(123) == {:error, :invalid_label}
    end
  end

  describe "label_to_verdict!/1" do
    test "parses valid labels" do
      assert NLI.label_to_verdict!("ENTAILMENT") == :entailment
      assert NLI.label_to_verdict!("CONTRADICTION") == :contradiction
      assert NLI.label_to_verdict!("NEUTRAL") == :neutral
    end

    test "raises ArgumentError for invalid labels" do
      assert_raise ArgumentError, ~r/Invalid NLI label/, fn ->
        NLI.label_to_verdict!("INVALID")
      end
    end
  end

  describe "valid_label?/1" do
    test "returns true for valid labels" do
      assert NLI.valid_label?("ENTAILMENT")
      assert NLI.valid_label?("CONTRADICTION")
      assert NLI.valid_label?("NEUTRAL")
    end

    test "returns false for lowercase labels" do
      refute NLI.valid_label?("entailment")
      refute NLI.valid_label?("contradiction")
      refute NLI.valid_label?("neutral")
    end

    test "returns false for invalid labels" do
      refute NLI.valid_label?("INVALID")
      refute NLI.valid_label?("")
    end

    test "returns false for non-string input" do
      refute NLI.valid_label?(:entailment)
      refute NLI.valid_label?(nil)
    end
  end

  describe "valid_labels/0" do
    test "returns all valid labels" do
      labels = NLI.valid_labels()
      assert labels == ["ENTAILMENT", "CONTRADICTION", "NEUTRAL"]
    end
  end

  describe "valid_verdicts/0" do
    test "returns all valid verdicts" do
      verdicts = NLI.valid_verdicts()
      assert verdicts == [:entailment, :contradiction, :neutral]
    end
  end

  describe "valid_verdict?/1" do
    test "returns true for valid verdicts" do
      assert NLI.valid_verdict?(:entailment)
      assert NLI.valid_verdict?(:contradiction)
      assert NLI.valid_verdict?(:neutral)
    end

    test "returns false for invalid verdicts" do
      refute NLI.valid_verdict?(:invalid)
      refute NLI.valid_verdict?(:unknown)
    end

    test "returns false for non-atom input" do
      refute NLI.valid_verdict?("entailment")
      refute NLI.valid_verdict?(nil)
    end
  end

  describe "round-trip conversion" do
    test "verdict -> label -> verdict preserves value" do
      for verdict <- [:entailment, :contradiction, :neutral] do
        label = NLI.verdict_to_label(verdict)
        assert {:ok, ^verdict} = NLI.label_to_verdict(label)
      end
    end
  end
end
