defmodule MedlumLlm.CVL.LabelingGuidelinesTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.LabelingGuidelines

  describe "full_guidelines/0" do
    test "returns complete guidelines structure" do
      guidelines = LabelingGuidelines.full_guidelines()

      assert is_map(guidelines)
      assert Map.has_key?(guidelines, :task_overview)
      assert Map.has_key?(guidelines, :verdicts)
      assert Map.has_key?(guidelines, :confidence_scale)
      assert Map.has_key?(guidelines, :evidence_quality)
      assert Map.has_key?(guidelines, :decision_tree)
      assert Map.has_key?(guidelines, :examples)
      assert Map.has_key?(guidelines, :common_pitfalls)
      assert Map.has_key?(guidelines, :clinical_considerations)
      assert Map.has_key?(guidelines, :quality_standards)
    end
  end

  describe "task_overview/0" do
    test "returns task description" do
      overview = LabelingGuidelines.task_overview()

      assert is_binary(overview)
      assert String.contains?(overview, "NLI")
      assert String.contains?(overview, "premise")
      assert String.contains?(overview, "hypothesis")
    end
  end

  describe "verdict_descriptions/0" do
    test "includes all three verdicts" do
      verdicts = LabelingGuidelines.verdict_descriptions()

      assert Map.has_key?(verdicts, :entailment)
      assert Map.has_key?(verdicts, :contradiction)
      assert Map.has_key?(verdicts, :neutral)
    end

    test "each verdict has label, description, and examples" do
      verdicts = LabelingGuidelines.verdict_descriptions()

      for {_key, verdict} <- verdicts do
        assert Map.has_key?(verdict, :label)
        assert Map.has_key?(verdict, :short_description)
        assert Map.has_key?(verdict, :full_description)
        assert Map.has_key?(verdict, :examples)
      end
    end

    test "entailment has correct label" do
      verdicts = LabelingGuidelines.verdict_descriptions()

      assert verdicts.entailment.label == "ENTAILMENT"
    end

    test "contradiction has correct label" do
      verdicts = LabelingGuidelines.verdict_descriptions()

      assert verdicts.contradiction.label == "CONTRADICTION"
    end

    test "neutral has correct label" do
      verdicts = LabelingGuidelines.verdict_descriptions()

      assert verdicts.neutral.label == "NEUTRAL"
    end
  end

  describe "confidence_scale/0" do
    test "has all 5 levels" do
      scale = LabelingGuidelines.confidence_scale()

      assert Map.has_key?(scale, 1)
      assert Map.has_key?(scale, 2)
      assert Map.has_key?(scale, 3)
      assert Map.has_key?(scale, 4)
      assert Map.has_key?(scale, 5)
    end

    test "each level has label and description" do
      scale = LabelingGuidelines.confidence_scale()

      for level <- 1..5 do
        assert Map.has_key?(scale[level], :label)
        assert Map.has_key?(scale[level], :description)
        assert Map.has_key?(scale[level], :guidance)
      end
    end
  end

  describe "evidence_quality_scale/0" do
    test "has all quality options" do
      scale = LabelingGuidelines.evidence_quality_scale()

      assert Map.has_key?(scale, :clear)
      assert Map.has_key?(scale, :partial)
      assert Map.has_key?(scale, :ambiguous)
      assert Map.has_key?(scale, :missing)
    end

    test "each option has label and description" do
      scale = LabelingGuidelines.evidence_quality_scale()

      for {_key, option} <- scale do
        assert Map.has_key?(option, :label)
        assert Map.has_key?(option, :description)
      end
    end
  end

  describe "decision_tree/0" do
    test "returns list of steps" do
      tree = LabelingGuidelines.decision_tree()

      assert is_list(tree)
      assert length(tree) >= 3
    end

    test "each step has question and branches" do
      tree = LabelingGuidelines.decision_tree()

      for step <- tree do
        assert Map.has_key?(step, :step)
        assert Map.has_key?(step, :question)
      end
    end

    test "steps are numbered sequentially" do
      tree = LabelingGuidelines.decision_tree()
      step_numbers = Enum.map(tree, & &1.step)

      assert step_numbers == Enum.sort(step_numbers)
    end
  end

  describe "examples/0" do
    test "includes examples for all verdict types" do
      examples = LabelingGuidelines.examples()
      types = Enum.map(examples, & &1.type)

      assert :entailment in types
      assert :contradiction in types
      assert :neutral in types
    end

    test "each example has required fields" do
      examples = LabelingGuidelines.examples()

      for example <- examples do
        assert Map.has_key?(example, :premise)
        assert Map.has_key?(example, :hypothesis)
        assert Map.has_key?(example, :verdict)
        assert Map.has_key?(example, :confidence)
        assert Map.has_key?(example, :reasoning)
      end
    end
  end

  describe "common_pitfalls/0" do
    test "returns list of pitfalls" do
      pitfalls = LabelingGuidelines.common_pitfalls()

      assert is_list(pitfalls)
      assert length(pitfalls) >= 3
    end

    test "each pitfall has description and correction" do
      pitfalls = LabelingGuidelines.common_pitfalls()

      for pitfall <- pitfalls do
        assert Map.has_key?(pitfall, :pitfall)
        assert Map.has_key?(pitfall, :description)
        assert Map.has_key?(pitfall, :correction)
      end
    end
  end

  describe "clinical_considerations/0" do
    test "returns list of considerations" do
      considerations = LabelingGuidelines.clinical_considerations()

      assert is_list(considerations)
      assert length(considerations) >= 2
    end

    test "each consideration has topic and guidance" do
      considerations = LabelingGuidelines.clinical_considerations()

      for consideration <- considerations do
        assert Map.has_key?(consideration, :topic)
        assert Map.has_key?(consideration, :guidance)
      end
    end
  end

  describe "quality_standards/0" do
    test "includes agreement threshold" do
      standards = LabelingGuidelines.quality_standards()

      assert Map.has_key?(standards, :agreement_threshold)
      assert standards.agreement_threshold == 0.80
    end

    test "includes min labels per sample" do
      standards = LabelingGuidelines.quality_standards()

      assert Map.has_key?(standards, :min_labels_per_sample)
      assert standards.min_labels_per_sample == 3
    end
  end

  describe "to_markdown/0" do
    test "generates markdown documentation" do
      markdown = LabelingGuidelines.to_markdown()

      assert is_binary(markdown)
      assert String.contains?(markdown, "# CVL NLI Labeling Guidelines")
      assert String.contains?(markdown, "## Verdict Options")
      assert String.contains?(markdown, "ENTAILMENT")
      assert String.contains?(markdown, "CONTRADICTION")
      assert String.contains?(markdown, "NEUTRAL")
    end

    test "includes confidence scale" do
      markdown = LabelingGuidelines.to_markdown()

      assert String.contains?(markdown, "## Confidence Scale")
    end

    test "includes examples section" do
      markdown = LabelingGuidelines.to_markdown()

      assert String.contains?(markdown, "## Examples")
    end

    test "includes common pitfalls" do
      markdown = LabelingGuidelines.to_markdown()

      assert String.contains?(markdown, "## Common Pitfalls")
    end
  end
end
