defmodule MedlumLlm.Eval.PromptsTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Eval.Prompts

  describe "format/2" do
    test "formats zero_shot_mcq template" do
      sample = %{
        question: "What is diabetes?",
        options: ["A. A disease affecting blood sugar", "B. A type of food", "C. An exercise", "D. A medicine"]
      }

      prompt = Prompts.format(:zero_shot_mcq, sample)

      assert prompt =~ "What is diabetes?"
      assert prompt =~ "A. A disease affecting blood sugar"
      assert prompt =~ "B. A type of food"
      assert prompt =~ "Answer with only the letter"
    end

    test "formats chain_of_thought_mcq template" do
      sample = %{
        question: "What causes hypertension?",
        options: ["A. High blood pressure", "B. Low blood pressure", "C. Normal pressure", "D. No pressure"]
      }

      prompt = Prompts.format(:chain_of_thought_mcq, sample)

      assert prompt =~ "What causes hypertension?"
      assert prompt =~ "Let's think through this step by step"
    end

    test "formats zero_shot_binary_qa template" do
      sample = %{
        context: "A study found that exercise reduces heart disease risk.",
        question: "Does exercise help prevent heart disease?"
      }

      prompt = Prompts.format(:zero_shot_binary_qa, sample)

      assert prompt =~ "exercise reduces heart disease risk"
      assert prompt =~ "Does exercise help prevent heart disease?"
      assert prompt =~ "yes/no/maybe"
    end

    test "formats reasoning_eval template" do
      sample = %{question: "Calculate the BMI for a patient weighing 70kg and 1.75m tall"}

      prompt = Prompts.format(:reasoning_eval, sample)

      assert prompt =~ "Calculate the BMI"
      assert prompt =~ "Solution:"
    end
  end

  describe "get_template/1" do
    test "returns template string" do
      template = Prompts.get_template(:zero_shot_mcq)
      assert is_binary(template)
      assert template =~ "Answer the following medical question"
    end

    test "returns nil for unknown template" do
      assert Prompts.get_template(:unknown) == nil
    end
  end

  describe "list_templates/0" do
    test "returns all template names" do
      templates = Prompts.list_templates()
      assert :zero_shot_mcq in templates
      assert :few_shot_mcq in templates
      assert :chain_of_thought_mcq in templates
      assert :zero_shot_binary_qa in templates
      assert :reasoning_eval in templates
    end
  end

  describe "parse_mcq_response/1" do
    test "parses direct letter" do
      assert "A" = Prompts.parse_mcq_response("A")
      assert "B" = Prompts.parse_mcq_response("b")
      assert "C" = Prompts.parse_mcq_response("C")
      assert "D" = Prompts.parse_mcq_response("d")
    end

    test "parses 'Answer: X' format" do
      assert "B" = Prompts.parse_mcq_response("Answer: B")
      assert "C" = Prompts.parse_mcq_response("answer: c")
    end

    test "parses 'The answer is X' format" do
      assert "A" = Prompts.parse_mcq_response("The answer is A")
      assert "D" = Prompts.parse_mcq_response("the correct answer is D")
    end

    test "parses parenthesized letter" do
      assert "A" = Prompts.parse_mcq_response("(A)")
      assert "B" = Prompts.parse_mcq_response("The correct choice is (B)")
    end

    test "parses letter at start" do
      assert "A" = Prompts.parse_mcq_response("A is correct because...")
      assert "B" = Prompts.parse_mcq_response("B")
    end

    test "parses letter with period/colon" do
      assert "A" = Prompts.parse_mcq_response("A. Because it is correct")
      assert "C" = Prompts.parse_mcq_response("C: This is the answer")
    end

    test "returns nil for unparseable response" do
      assert nil == Prompts.parse_mcq_response("I don't know")
      assert nil == Prompts.parse_mcq_response("The patient has diabetes")
      assert nil == Prompts.parse_mcq_response("")
    end
  end

  describe "parse_binary_response/1" do
    test "parses yes responses" do
      assert "yes" = Prompts.parse_binary_response("yes")
      assert "yes" = Prompts.parse_binary_response("Yes, that is correct")
      assert "yes" = Prompts.parse_binary_response("YES")
    end

    test "parses no responses" do
      assert "no" = Prompts.parse_binary_response("no")
      assert "no" = Prompts.parse_binary_response("No, that is incorrect")
      assert "no" = Prompts.parse_binary_response("NO")
    end

    test "parses maybe responses" do
      assert "maybe" = Prompts.parse_binary_response("maybe")
      assert "maybe" = Prompts.parse_binary_response("Maybe, more research is needed")
      assert "maybe" = Prompts.parse_binary_response("It's uncertain")
    end

    test "returns nil for unparseable" do
      assert nil == Prompts.parse_binary_response("I'm not sure about this specific claim")
    end
  end

  describe "parse_cot_response/1" do
    test "extracts reasoning and answer with 'therefore'" do
      response = "Step 1: Consider the symptoms. Step 2: Check the risk factors. Therefore, the answer is A."
      result = Prompts.parse_cot_response(response)

      assert result.reasoning =~ "Step 1"
      assert result.reasoning =~ "Step 2"
      assert result.answer == "A"
    end

    test "extracts reasoning and answer with 'thus'" do
      response = "The patient shows signs of infection. Thus, the answer is B."
      result = Prompts.parse_cot_response(response)

      assert result.reasoning =~ "signs of infection"
      assert result.answer == "B"
    end

    test "extracts reasoning and answer with 'final answer'" do
      response = "Based on the analysis, the final answer is C."
      result = Prompts.parse_cot_response(response)

      assert result.answer == "C"
    end

    test "handles response without clear answer marker" do
      response = "This is a complex case. The most likely diagnosis is related to A."
      result = Prompts.parse_cot_response(response)

      assert result.reasoning =~ "complex case"
      assert result.answer == "A"
    end

    test "returns nil answer if not found" do
      response = "This is a complex case with no clear answer."
      result = Prompts.parse_cot_response(response)

      assert result.reasoning =~ "complex case"
      assert result.answer == nil
    end
  end

  describe "validate_sample/2" do
    test "validates zero_shot_mcq sample" do
      valid = %{question: "Q?", options: ["A", "B"]}
      assert :ok = Prompts.validate_sample(:zero_shot_mcq, valid)

      invalid = %{question: "Q?"}
      assert {:error, {:missing_fields, [:options]}} = Prompts.validate_sample(:zero_shot_mcq, invalid)
    end

    test "validates zero_shot_binary_qa sample" do
      valid = %{question: "Q?", context: "Some context"}
      assert :ok = Prompts.validate_sample(:zero_shot_binary_qa, valid)

      invalid = %{question: "Q?"}
      assert {:error, {:missing_fields, [:context]}} = Prompts.validate_sample(:zero_shot_binary_qa, invalid)
    end
  end

  describe "required_fields_for/1" do
    test "returns fields for zero_shot_mcq" do
      assert [:question, :options] = Prompts.required_fields_for(:zero_shot_mcq)
    end

    test "returns fields for few_shot_mcq" do
      assert [:question, :options, :examples] = Prompts.required_fields_for(:few_shot_mcq)
    end

    test "returns empty list for unknown template" do
      assert [] = Prompts.required_fields_for(:unknown)
    end
  end

  describe "format_options/1" do
    test "adds letter prefixes to options" do
      options = ["First option", "Second option", "Third option", "Fourth option"]
      formatted = Prompts.format_options(options)

      assert formatted == ["A. First option", "B. Second option", "C. Third option", "D. Fourth option"]
    end

    test "handles more than 4 options" do
      options = Enum.map(1..6, fn i -> "Option #{i}" end)
      formatted = Prompts.format_options(options)

      assert List.first(formatted) == "A. Option 1"
      assert List.last(formatted) == "F. Option 6"
    end
  end

  describe "options_have_letters?/1" do
    test "returns true for options with letters" do
      assert Prompts.options_have_letters?(["A. First", "B. Second"])
      assert Prompts.options_have_letters?(["A: First", "B: Second"])
    end

    test "returns false for options without letters" do
      refute Prompts.options_have_letters?(["First", "Second"])
      refute Prompts.options_have_letters?(["1. First", "2. Second"])
    end
  end

  describe "normalize_sample/1" do
    test "adds letter prefixes to options without them" do
      sample = %{question: "Q?", options: ["First", "Second"]}
      normalized = Prompts.normalize_sample(sample)

      assert normalized.options == ["A. First", "B. Second"]
    end

    test "preserves options that already have letters" do
      sample = %{question: "Q?", options: ["A. First", "B. Second"]}
      normalized = Prompts.normalize_sample(sample)

      assert normalized.options == ["A. First", "B. Second"]
    end

    test "handles sample without options" do
      sample = %{question: "Q?", context: "Some context"}
      normalized = Prompts.normalize_sample(sample)

      assert normalized == sample
    end
  end
end
