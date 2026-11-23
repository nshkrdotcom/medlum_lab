defmodule MedlumLlm.Datasets.PreprocessorTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Datasets.Preprocessor

  @moduletag :unit

  describe "mcq/1" do
    test "normalizes MedQA-style sample with options array" do
      sample = %{
        "id" => "q001",
        "question" => "What is the diagnosis?",
        "options" => ["Diabetes", "Hypertension", "COPD", "Asthma"],
        "answer" => 0
      }

      result = Preprocessor.mcq(sample)

      assert result.id == "q001"
      assert result.question == "What is the diagnosis?"
      assert result.options == ["A. Diabetes", "B. Hypertension", "C. COPD", "D. Asthma"]
      assert result.answer == "A"
    end

    test "handles letter answers" do
      sample = %{
        "question" => "Test?",
        "options" => ["A", "B", "C", "D"],
        "answer" => "B"
      }

      result = Preprocessor.mcq(sample)
      assert result.answer == "B"
    end

    test "handles lowercase letter answers" do
      sample = %{
        "question" => "Test?",
        "options" => ["A", "B", "C", "D"],
        "answer" => "c"
      }

      result = Preprocessor.mcq(sample)
      assert result.answer == "C"
    end

    test "handles MedMCQA-style options (opa, opb, opc, opd)" do
      sample = %{
        "question" => "What is the treatment?",
        "opa" => "Surgery",
        "opb" => "Medication",
        "opc" => "Therapy",
        "opd" => "Observation",
        "cop" => 1
      }

      result = Preprocessor.mcq(sample)

      assert result.options == [
               "A. Surgery",
               "B. Medication",
               "C. Therapy",
               "D. Observation"
             ]

      assert result.answer == "B"
    end

    test "handles choices key for options" do
      sample = %{
        "question" => "Which is correct?",
        "choices" => ["Option A", "Option B", "Option C", "Option D"],
        "answer" => 2
      }

      result = Preprocessor.mcq(sample)

      assert result.options == ["A. Option A", "B. Option B", "C. Option C", "D. Option D"]
      assert result.answer == "C"
    end

    test "extracts explanation and subject" do
      sample = %{
        "question" => "Test?",
        "options" => ["A", "B", "C", "D"],
        "answer" => 0,
        "exp" => "This is the explanation",
        "subject" => "cardiology"
      }

      result = Preprocessor.mcq(sample)

      assert result.explanation == "This is the explanation"
      assert result.subject == "cardiology"
    end

    test "generates id if not present" do
      sample = %{
        "question" => "Test?",
        "options" => ["A", "B", "C", "D"],
        "answer" => 0
      }

      result = Preprocessor.mcq(sample)

      assert is_binary(result.id)
      assert String.length(result.id) > 0
    end
  end

  describe "binary_qa/1" do
    test "normalizes PubMedQA-style sample" do
      sample = %{
        "QUESTION" => "Is this effective?",
        "CONTEXTS" => ["Context 1", "Context 2"],
        "final_decision" => "yes"
      }

      result = Preprocessor.binary_qa(sample)

      assert result.question == "Is this effective?"
      assert result.context == "Context 1\n\nContext 2"
      assert result.answer == "yes"
      assert result.options == ["yes", "no", "maybe"]
    end

    test "normalizes various yes/no/maybe formats" do
      # Yes variants
      assert Preprocessor.binary_qa(%{"final_decision" => "yes"}).answer == "yes"
      assert Preprocessor.binary_qa(%{"final_decision" => "Yes"}).answer == "yes"
      assert Preprocessor.binary_qa(%{"final_decision" => "YES"}).answer == "yes"
      assert Preprocessor.binary_qa(%{"answer" => 1}).answer == "yes"
      assert Preprocessor.binary_qa(%{"answer" => "1"}).answer == "yes"

      # No variants
      assert Preprocessor.binary_qa(%{"final_decision" => "no"}).answer == "no"
      assert Preprocessor.binary_qa(%{"final_decision" => "No"}).answer == "no"
      assert Preprocessor.binary_qa(%{"answer" => 0}).answer == "no"
      assert Preprocessor.binary_qa(%{"answer" => "0"}).answer == "no"

      # Maybe variants
      assert Preprocessor.binary_qa(%{"final_decision" => "maybe"}).answer == "maybe"
      assert Preprocessor.binary_qa(%{"final_decision" => "Maybe"}).answer == "maybe"
      assert Preprocessor.binary_qa(%{"answer" => 2}).answer == "maybe"
      assert Preprocessor.binary_qa(%{"answer" => "2"}).answer == "maybe"
    end

    test "extracts context from various fields" do
      # CONTEXTS array
      result = Preprocessor.binary_qa(%{"CONTEXTS" => ["A", "B"]})
      assert result.context == "A\n\nB"

      # context string
      result = Preprocessor.binary_qa(%{"context" => "Single context"})
      assert result.context == "Single context"

      # abstract
      result = Preprocessor.binary_qa(%{"abstract" => "Abstract text"})
      assert result.context == "Abstract text"
    end

    test "extracts metadata" do
      sample = %{
        "QUESTION" => "Test?",
        "PUBMED_ID" => "12345",
        "MESHES" => ["term1", "term2"],
        "LONG_ANSWER" => "Long explanation here"
      }

      result = Preprocessor.binary_qa(sample)

      assert result.meta.pubmed_id == "12345"
      assert result.meta.mesh_terms == ["term1", "term2"]
      assert result.long_answer == "Long explanation here"
    end
  end

  describe "reasoning/1" do
    test "normalizes reasoning sample" do
      sample = %{
        "question" => "Diagnose this patient",
        "reasoning" => "Step 1: Consider symptoms...\nStep 2: ...",
        "answer" => "The diagnosis is..."
      }

      result = Preprocessor.reasoning(sample)

      assert result.question == "Diagnose this patient"
      assert result.reasoning == "Step 1: Consider symptoms...\nStep 2: ..."
      assert result.answer == "The diagnosis is..."
    end

    test "handles instruction/cot/response fields" do
      sample = %{
        "instruction" => "Analyze this case",
        "cot" => "Chain of thought...",
        "response" => "Final answer"
      }

      result = Preprocessor.reasoning(sample)

      assert result.question == "Analyze this case"
      assert result.reasoning == "Chain of thought..."
      assert result.answer == "Final answer"
    end

    test "handles chain_of_thought field" do
      sample = %{
        "question" => "Test",
        "chain_of_thought" => "Reasoning steps..."
      }

      result = Preprocessor.reasoning(sample)

      assert result.reasoning == "Reasoning steps..."
    end

    test "extracts metadata" do
      sample = %{
        "question" => "Test",
        "source" => "MedQA",
        "difficulty" => "hard"
      }

      result = Preprocessor.reasoning(sample)

      assert result.meta.source == "MedQA"
      assert result.meta.difficulty == "hard"
    end
  end

  describe "mmlu_medical/1" do
    test "includes medical subjects" do
      sample = %{
        "subject" => "anatomy",
        "question" => "What is the largest bone?",
        "A" => "Femur",
        "B" => "Tibia",
        "C" => "Humerus",
        "D" => "Radius",
        "answer" => "A"
      }

      result = Preprocessor.mmlu_medical(sample)

      assert result != nil
      assert result.subject == "anatomy"
      assert result.question == "What is the largest bone?"
      assert result.options == ["A. Femur", "B. Tibia", "C. Humerus", "D. Radius"]
      assert result.answer == "A"
    end

    test "filters out non-medical subjects" do
      sample = %{
        "subject" => "world_history",
        "question" => "What year did WWII end?",
        "A" => "1943",
        "B" => "1944",
        "C" => "1945",
        "D" => "1946",
        "answer" => "C"
      }

      assert Preprocessor.mmlu_medical(sample) == nil
    end

    test "handles category field instead of subject" do
      sample = %{
        "category" => "clinical_knowledge",
        "question" => "Test",
        "A" => "A",
        "B" => "B",
        "C" => "C",
        "D" => "D",
        "answer" => "A"
      }

      result = Preprocessor.mmlu_medical(sample)
      assert result.subject == "clinical_knowledge"
    end

    test "accepts all 7 medical subjects" do
      medical_subjects = [
        "anatomy",
        "clinical_knowledge",
        "college_biology",
        "college_medicine",
        "medical_genetics",
        "professional_medicine",
        "virology"
      ]

      for subject <- medical_subjects do
        sample = %{
          "subject" => subject,
          "question" => "Test",
          "A" => "A",
          "B" => "B",
          "C" => "C",
          "D" => "D",
          "answer" => "A"
        }

        result = Preprocessor.mmlu_medical(sample)
        assert result != nil, "Subject #{subject} should be included"
        assert result.subject == subject
      end
    end
  end

  describe "n2c2_medication/1" do
    test "normalizes medication extraction sample" do
      sample = %{
        "id" => "doc001",
        "text" => "Patient takes aspirin 81mg daily",
        "entities" => [
          %{"text" => "aspirin", "type" => "medication", "start" => 14, "end" => 21},
          %{"text" => "81mg", "type" => "dosage", "start" => 22, "end" => 26}
        ],
        "doc_id" => "patient_001"
      }

      result = Preprocessor.n2c2_medication(sample)

      assert result.id == "doc001"
      assert result.text == "Patient takes aspirin 81mg daily"
      assert length(result.entities) == 2

      entity = hd(result.entities)
      assert entity.text == "aspirin"
      assert entity.type == "medication"
      assert entity.start == 14
      assert entity.end_pos == 21

      assert result.meta.document_id == "patient_001"
    end

    test "handles alternative entity field names" do
      sample = %{
        "text" => "Test",
        "entities" => [
          %{"mention" => "drug", "label" => "med", "begin" => 0, "end" => 4}
        ]
      }

      result = Preprocessor.n2c2_medication(sample)

      entity = hd(result.entities)
      assert entity.text == "drug"
      assert entity.type == "med"
      assert entity.start == 0
    end

    test "handles missing entities" do
      sample = %{"text" => "No entities here"}

      result = Preprocessor.n2c2_medication(sample)

      assert result.entities == []
    end
  end

  describe "summarization/1" do
    test "normalizes summarization sample" do
      sample = %{
        "id" => "sum001",
        "src" => "Full clinical note text...",
        "tgt" => "Brief summary...",
        "doc_id" => "note_001",
        "note_type" => "discharge"
      }

      result = Preprocessor.summarization(sample)

      assert result.id == "sum001"
      assert result.source == "Full clinical note text..."
      assert result.target == "Brief summary..."
      assert result.meta.document_id == "note_001"
      assert result.meta.note_type == "discharge"
    end

    test "handles alternative field names" do
      # source/document
      result = Preprocessor.summarization(%{"source" => "Source text"})
      assert result.source == "Source text"

      result = Preprocessor.summarization(%{"document" => "Doc text"})
      assert result.source == "Doc text"

      # target/summary
      result = Preprocessor.summarization(%{"target" => "Target text"})
      assert result.target == "Target text"

      result = Preprocessor.summarization(%{"summary" => "Summary text"})
      assert result.target == "Summary text"
    end
  end

  describe "id generation" do
    test "uses existing id if present" do
      sample = %{"id" => "existing_id", "question" => "Test"}
      assert Preprocessor.mcq(sample).id == "existing_id"
    end

    test "uses uid if no id" do
      sample = %{"uid" => "uid_123", "question" => "Test"}
      assert Preprocessor.mcq(sample).id == "uid_123"
    end

    test "uses idx if no id or uid" do
      sample = %{"idx" => "idx_456", "question" => "Test"}
      assert Preprocessor.mcq(sample).id == "idx_456"
    end

    test "generates random id if none present" do
      sample = %{"question" => "Test"}

      result = Preprocessor.mcq(sample)

      assert is_binary(result.id)
      # Should be hex encoded, so 16 characters
      assert String.length(result.id) == 16
    end
  end
end
