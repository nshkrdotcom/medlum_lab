defmodule MedlumLlm.Datasets.ValidatorsTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Datasets.Validators
  alias DatasetsEx.Dataset

  # Test data helpers
  defp mcq_dataset(items) do
    Dataset.new("test_mcq", data: items, schema: :medical_mcq)
  end

  defp binary_qa_dataset(items) do
    Dataset.new("test_binary_qa", data: items, schema: :medical_binary_qa)
  end

  defp ner_dataset(items) do
    Dataset.new("test_ner", data: items, schema: :medical_ner)
  end

  defp cvl_dataset(items) do
    Dataset.new("test_cvl", data: items, schema: :medical_cvl)
  end

  defp reasoning_dataset(items) do
    Dataset.new("test_reasoning", data: items, schema: :medical_reasoning)
  end

  describe "validate_mcq/2" do
    test "validates valid MCQ dataset" do
      items = [
        %{
          question: "What is the mechanism of action of metformin?",
          options: ["Increases insulin secretion", "Decreases hepatic gluconeogenesis",
                   "Blocks glucose absorption", "Increases insulin sensitivity"],
          correct_answer: "B"
        }
      ]

      {:ok, report} = Validators.validate_mcq(mcq_dataset(items))

      assert report.valid == true
      assert report.total_items == 1
      assert report.valid_items == 1
      assert report.invalid_items == 0
      assert report.errors == []
    end

    test "rejects MCQ with missing question" do
      items = [
        %{
          options: ["A", "B", "C", "D"],
          correct_answer: "A"
        }
      ]

      {:ok, report} = Validators.validate_mcq(mcq_dataset(items))

      assert report.valid == false
      assert report.invalid_items == 1
      assert Enum.any?(report.errors, &String.contains?(&1, "missing required fields"))
    end

    test "rejects MCQ with wrong number of options" do
      items = [
        %{
          question: "Test question?",
          options: ["A", "B", "C"],  # Only 3 options
          correct_answer: "A"
        }
      ]

      {:ok, report} = Validators.validate_mcq(mcq_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "exactly 4 items"))
    end

    test "rejects MCQ with invalid answer" do
      items = [
        %{
          question: "Test question?",
          options: ["A", "B", "C", "D"],
          correct_answer: "E"  # Invalid
        }
      ]

      {:ok, report} = Validators.validate_mcq(mcq_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "correct_answer"))
    end

    test "accepts numeric answer (0-3)" do
      items = [
        %{
          question: "Test question?",
          options: ["A", "B", "C", "D"],
          correct_answer: 1
        }
      ]

      {:ok, report} = Validators.validate_mcq(mcq_dataset(items))

      assert report.valid == true
    end

    test "rejects MCQ with duplicate options" do
      items = [
        %{
          question: "Test question?",
          options: ["Same", "Same", "C", "D"],  # Duplicates
          correct_answer: "A"
        }
      ]

      {:ok, report} = Validators.validate_mcq(mcq_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "duplicates"))
    end

    test "rejects MCQ with empty options" do
      items = [
        %{
          question: "Test question?",
          options: ["A", "", "C", "D"],  # Empty option
          correct_answer: "A"
        }
      ]

      {:ok, report} = Validators.validate_mcq(mcq_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "empty"))
    end

    test "validates multiple items and reports all errors" do
      items = [
        %{question: "Valid?", options: ["A", "B", "C", "D"], correct_answer: "A"},
        %{question: "Missing options?", correct_answer: "A"},
        %{question: "Wrong answer?", options: ["A", "B", "C", "D"], correct_answer: "Z"}
      ]

      {:ok, report} = Validators.validate_mcq(mcq_dataset(items))

      assert report.valid == false
      assert report.total_items == 3
      assert report.valid_items == 1
      assert report.invalid_items == 2
    end

    test "supports custom checks" do
      custom_check = fn item ->
        if String.contains?(item.question, "?") do
          :ok
        else
          {:error, "Question must contain question mark"}
        end
      end

      items = [
        %{question: "Valid question?", options: ["A", "B", "C", "D"], correct_answer: "A"},
        %{question: "Missing question mark", options: ["A", "B", "C", "D"], correct_answer: "A"}
      ]

      {:ok, report} = Validators.validate_mcq(mcq_dataset(items), custom_checks: [custom_check])

      assert report.valid == false
      assert report.valid_items == 1
      assert Enum.any?(report.errors, &String.contains?(&1, "question mark"))
    end
  end

  describe "validate_binary_qa/2" do
    test "validates valid binary QA dataset" do
      items = [
        %{
          question: "Is aspirin effective for pain relief?",
          context: "Aspirin is a widely used analgesic medication...",
          answer: "yes"
        }
      ]

      {:ok, report} = Validators.validate_binary_qa(binary_qa_dataset(items))

      assert report.valid == true
    end

    test "accepts yes/no/maybe answers" do
      items = [
        %{question: "Q1?", context: "Context", answer: "yes"},
        %{question: "Q2?", context: "Context", answer: "no"},
        %{question: "Q3?", context: "Context", answer: "maybe"}
      ]

      {:ok, report} = Validators.validate_binary_qa(binary_qa_dataset(items))

      assert report.valid == true
      assert report.valid_items == 3
    end

    test "rejects invalid answer" do
      items = [
        %{question: "Q?", context: "Context", answer: "possibly"}
      ]

      {:ok, report} = Validators.validate_binary_qa(binary_qa_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "yes/no/maybe"))
    end

    test "rejects empty context" do
      items = [
        %{question: "Q?", context: "", answer: "yes"}
      ]

      {:ok, report} = Validators.validate_binary_qa(binary_qa_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "context"))
    end

    test "can require explanation" do
      items = [
        %{question: "Q?", context: "Context", answer: "yes"}  # No explanation
      ]

      {:ok, report} = Validators.validate_binary_qa(binary_qa_dataset(items),
        require_explanation: true
      )

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "explanation"))
    end

    test "passes when explanation is provided and required" do
      items = [
        %{question: "Q?", context: "Context", answer: "yes", explanation: "Because..."}
      ]

      {:ok, report} = Validators.validate_binary_qa(binary_qa_dataset(items),
        require_explanation: true
      )

      assert report.valid == true
    end
  end

  describe "validate_ner/2" do
    test "validates valid NER dataset" do
      items = [
        %{
          text: "The patient has diabetes mellitus type 2.",
          entities: [
            %{text: "diabetes mellitus type 2", type: "DISEASE", start: 16, end_pos: 40}
          ]
        }
      ]

      {:ok, report} = Validators.validate_ner(ner_dataset(items))

      assert report.valid == true
    end

    test "validates empty entities list" do
      items = [
        %{text: "No diseases mentioned.", entities: []}
      ]

      {:ok, report} = Validators.validate_ner(ner_dataset(items))

      assert report.valid == true
    end

    test "rejects entity with invalid span (end < start)" do
      items = [
        %{
          text: "The patient has diabetes.",
          entities: [%{text: "diabetes", type: "DISEASE", start: 20, end_pos: 10}]
        }
      ]

      {:ok, report} = Validators.validate_ner(ner_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "invalid spans"))
    end

    test "rejects entity span out of text bounds" do
      items = [
        %{
          text: "Short text",
          entities: [%{text: "entity", type: "TYPE", start: 0, end_pos: 100}]
        }
      ]

      {:ok, report} = Validators.validate_ner(ner_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "exceed text length"))
    end

    test "rejects overlapping entities by default" do
      items = [
        %{
          text: "The patient has diabetes mellitus type 2.",
          entities: [
            %{text: "diabetes", type: "DISEASE", start: 16, end_pos: 24},
            %{text: "diabetes mellitus", type: "DISEASE", start: 16, end_pos: 33}  # Overlaps
          ]
        }
      ]

      {:ok, report} = Validators.validate_ner(ner_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "overlapping"))
    end

    test "allows overlapping entities when option set" do
      items = [
        %{
          text: "The patient has diabetes mellitus type 2.",
          entities: [
            %{text: "diabetes", type: "DISEASE", start: 16, end_pos: 24},
            %{text: "diabetes mellitus", type: "DISEASE", start: 16, end_pos: 33}
          ]
        }
      ]

      {:ok, report} = Validators.validate_ner(ner_dataset(items), allow_overlapping: true)

      assert report.valid == true
    end

    test "handles both :end and :end_pos keys" do
      items = [
        %{
          text: "The patient has diabetes.",
          entities: [%{text: "diabetes", type: "DISEASE", start: 16, end: 24}]
        }
      ]

      {:ok, report} = Validators.validate_ner(ner_dataset(items))

      assert report.valid == true
    end
  end

  describe "validate_cvl/2" do
    test "validates valid CVL dataset" do
      items = [
        %{
          premise: "The patient is on metformin 500mg BID.",
          hypothesis: "The patient takes metformin twice daily.",
          verdict: :entailment
        }
      ]

      {:ok, report} = Validators.validate_cvl(cvl_dataset(items))

      assert report.valid == true
    end

    test "accepts all valid verdicts" do
      items = [
        %{premise: "P1", hypothesis: "H1", verdict: :entailment},
        %{premise: "P2", hypothesis: "H2", verdict: :contradiction},
        %{premise: "P3", hypothesis: "H3", verdict: :neutral}
      ]

      {:ok, report} = Validators.validate_cvl(cvl_dataset(items))

      assert report.valid == true
      assert report.valid_items == 3
    end

    test "rejects invalid verdict" do
      items = [
        %{premise: "P", hypothesis: "H", verdict: :maybe}
      ]

      {:ok, report} = Validators.validate_cvl(cvl_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "verdict"))
    end

    test "rejects empty premise" do
      items = [
        %{premise: "", hypothesis: "Valid hypothesis", verdict: :entailment}
      ]

      {:ok, report} = Validators.validate_cvl(cvl_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "premise"))
    end

    test "rejects empty hypothesis" do
      items = [
        %{premise: "Valid premise", hypothesis: "   ", verdict: :entailment}
      ]

      {:ok, report} = Validators.validate_cvl(cvl_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "hypothesis"))
    end

    test "can require evidence" do
      items = [
        %{premise: "P", hypothesis: "H", verdict: :entailment}  # No evidence
      ]

      {:ok, report} = Validators.validate_cvl(cvl_dataset(items), require_evidence: true)

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "evidence"))
    end

    test "passes when evidence provided and required" do
      items = [
        %{premise: "P", hypothesis: "H", verdict: :entailment, evidence: ["Supporting fact"]}
      ]

      {:ok, report} = Validators.validate_cvl(cvl_dataset(items), require_evidence: true)

      assert report.valid == true
    end
  end

  describe "validate_reasoning/2" do
    test "validates valid reasoning dataset" do
      items = [
        %{
          question: "Why is insulin used in type 1 diabetes?",
          thinking: "Let me analyze this step by step. Type 1 diabetes is characterized by the destruction of beta cells in the pancreas, which are responsible for producing insulin. Without these cells, the body cannot produce its own insulin. Therefore, exogenous insulin is required.",
          answer: "Insulin is required in type 1 diabetes because the pancreas cannot produce it."
        }
      ]

      {:ok, report} = Validators.validate_reasoning(reasoning_dataset(items))

      assert report.valid == true
    end

    test "rejects short thinking" do
      items = [
        %{
          question: "Why?",
          thinking: "Short",  # Less than 50 chars
          answer: "Because."
        }
      ]

      {:ok, report} = Validators.validate_reasoning(reasoning_dataset(items))

      assert report.valid == false
      assert Enum.any?(report.errors, &String.contains?(&1, "at least"))
    end

    test "custom minimum thinking length" do
      items = [
        %{
          question: "Why?",
          thinking: "A bit longer than before but still short.",
          answer: "Answer."
        }
      ]

      {:ok, report} = Validators.validate_reasoning(reasoning_dataset(items),
        min_thinking_length: 30
      )

      assert report.valid == true
    end
  end

  describe "full_quality_check/3" do
    test "returns comprehensive report for MCQ" do
      items = [
        %{question: "Q1?", options: ["A", "B", "C", "D"], correct_answer: "A"},
        %{question: "Q2?", options: ["A", "B", "C", "D"], correct_answer: "B"},
        %{question: "Q2?", options: ["A", "B", "C", "D"], correct_answer: "B"}  # Duplicate
      ]

      {:ok, report} = Validators.full_quality_check(mcq_dataset(items), :mcq)

      assert Map.has_key?(report, :format_validation)
      assert Map.has_key?(report, :duplicates)
      assert Map.has_key?(report, :distribution)
      assert Map.has_key?(report, :profile)
      assert Map.has_key?(report, :overall_valid)
      assert report.format == :mcq
    end

    test "returns error for unknown format" do
      items = [%{data: "test"}]

      assert {:error, {:unknown_format, :invalid}} =
               Validators.full_quality_check(Dataset.new("test", data: items), :invalid)
    end

    test "combines format validation with profiling" do
      items = for i <- 1..10 do
        %{
          question: "Question #{i} with some text?",
          options: ["Option A", "Option B", "Option C", "Option D"],
          correct_answer: Enum.at(["A", "B", "C", "D"], rem(i, 4))
        }
      end

      {:ok, report} = Validators.full_quality_check(mcq_dataset(items), :mcq)

      assert report.format_validation.valid == true
      assert report.profile.total_items == 10
      assert Map.has_key?(report.profile, :text_stats)
      assert Map.has_key?(report.distribution, :distribution)
    end
  end

  describe "check_answer_not_in_question/1" do
    test "passes when answer not in question" do
      item = %{
        question: "What medication is used for diabetes?",
        options: ["Metformin", "Aspirin", "Ibuprofen", "Acetaminophen"],
        correct_answer: "A"
      }

      assert :ok = Validators.check_answer_not_in_question(item)
    end

    test "fails when answer appears in question" do
      item = %{
        question: "Is Metformin used for diabetes?",
        options: ["Metformin", "Aspirin", "Ibuprofen", "Acetaminophen"],
        correct_answer: "A"
      }

      assert {:error, msg} = Validators.check_answer_not_in_question(item)
      assert String.contains?(msg, "leakage")
    end

    test "case insensitive check" do
      item = %{
        question: "Is METFORMIN effective?",
        options: ["metformin", "Aspirin", "Ibuprofen", "Acetaminophen"],
        correct_answer: "A"
      }

      assert {:error, _} = Validators.check_answer_not_in_question(item)
    end
  end
end
