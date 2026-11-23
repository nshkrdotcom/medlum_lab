defmodule MedlumLlm.Datasets.Preprocessor do
  @moduledoc """
  Medical dataset preprocessing functions.

  Normalizes various dataset formats to a common schema, enabling
  consistent evaluation across different medical benchmarks.

  ## Normalized Sample Format

  All preprocessors output samples with a consistent structure:

      %{
        id: "unique_id",
        question: "The clinical question...",
        options: ["A. ...", "B. ...", "C. ...", "D. ..."],  # for MCQ
        answer: "A",  # normalized answer
        explanation: "...",  # if available
        subject: "cardiology",  # if available
        meta: %{}  # dataset-specific metadata
      }

  ## Preprocessors

    * `mcq/1` - Multiple-choice questions (MedQA, MedMCQA)
    * `binary_qa/1` - Yes/No/Maybe questions (PubMedQA)
    * `reasoning/1` - Chain-of-thought reasoning (ReasonMed)
    * `mmlu_medical/1` - MMLU medical subjects filter
    * `n2c2_medication/1` - Medication NER format
    * `summarization/1` - Clinical summarization format

  """

  @doc """
  Preprocess multiple-choice question format (MedQA, MedMCQA).

  Input varies by dataset but typically includes:
  - question: The question text
  - options/choices: Answer options
  - answer/cop: Correct answer index or letter

  ## Output

      %{
        id: string,
        question: string,
        options: [string],
        answer: string,  # "A", "B", "C", or "D"
        explanation: string | nil,
        subject: string | nil,
        meta: map
      }

  ## Examples

      sample = %{
        "question" => "What is the diagnosis?",
        "options" => ["Diabetes", "Hypertension", "COPD", "Asthma"],
        "answer" => 0
      }
      Preprocessor.mcq(sample)
      #=> %{
      #     id: "...",
      #     question: "What is the diagnosis?",
      #     options: ["A. Diabetes", "B. Hypertension", "C. COPD", "D. Asthma"],
      #     answer: "A",
      #     ...
      #   }

  """
  @spec mcq(map()) :: map()
  def mcq(sample) do
    %{
      id: get_id(sample),
      question: get_question(sample),
      options: normalize_options(sample),
      answer: normalize_answer(sample),
      explanation: sample["exp"] || sample["explanation"],
      subject: sample["subject"] || sample["topic"],
      meta: %{
        original_id: sample["id"] || sample["uid"],
        source: sample["source"]
      }
    }
  end

  @doc """
  Preprocess binary Q&A format (PubMedQA).

  ## Output

      %{
        id: string,
        question: string,
        context: string,
        options: ["yes", "no", "maybe"],
        answer: string,  # "yes", "no", or "maybe"
        long_answer: string | nil,
        meta: map
      }

  ## Examples

      sample = %{
        "QUESTION" => "Is this drug effective?",
        "CONTEXTS" => ["Study 1 results...", "Study 2 results..."],
        "final_decision" => "yes"
      }
      Preprocessor.binary_qa(sample)
      #=> %{
      #     question: "Is this drug effective?",
      #     context: "Study 1 results...\\n\\nStudy 2 results...",
      #     answer: "yes",
      #     ...
      #   }

  """
  @spec binary_qa(map()) :: map()
  def binary_qa(sample) do
    %{
      id: get_id(sample),
      question: sample["question"] || sample["QUESTION"],
      context: extract_context(sample),
      options: ["yes", "no", "maybe"],
      answer: normalize_binary_answer(sample),
      long_answer: sample["long_answer"] || sample["LONG_ANSWER"],
      meta: %{
        pubmed_id: sample["pubid"] || sample["PUBMED_ID"],
        mesh_terms: sample["MESHES"]
      }
    }
  end

  @doc """
  Preprocess reasoning format (ReasonMed, medical-o1).

  ## Output

      %{
        id: string,
        question: string,
        reasoning: string,
        answer: string,
        meta: map
      }

  ## Examples

      sample = %{
        "instruction" => "A patient presents with...",
        "cot" => "Step 1: Consider the symptoms...\\nStep 2: ...",
        "response" => "The most likely diagnosis is..."
      }
      Preprocessor.reasoning(sample)

  """
  @spec reasoning(map()) :: map()
  def reasoning(sample) do
    %{
      id: get_id(sample),
      question: sample["question"] || sample["instruction"],
      reasoning: sample["reasoning"] || sample["cot"] || sample["chain_of_thought"],
      answer: sample["answer"] || sample["response"],
      meta: %{
        source: sample["source"],
        difficulty: sample["difficulty"]
      }
    }
  end

  @doc """
  Preprocess MMLU medical subjects.

  Filters to medical subjects only, returning `nil` for non-medical subjects.
  This allows the pipeline to use `Stream.reject(&is_nil/1)` to filter.

  ## Medical Subjects

  - anatomy
  - clinical_knowledge
  - college_biology
  - college_medicine
  - medical_genetics
  - professional_medicine
  - virology

  ## Returns

  `map()` for medical subjects, `nil` for non-medical subjects.

  ## Examples

      # Medical subject - returns normalized sample
      Preprocessor.mmlu_medical(%{"subject" => "anatomy", ...})
      #=> %{subject: "anatomy", ...}

      # Non-medical subject - returns nil
      Preprocessor.mmlu_medical(%{"subject" => "world_history", ...})
      #=> nil

  """
  @spec mmlu_medical(map()) :: map() | nil
  def mmlu_medical(sample) do
    medical_subjects = [
      "anatomy",
      "clinical_knowledge",
      "college_biology",
      "college_medicine",
      "medical_genetics",
      "professional_medicine",
      "virology"
    ]

    subject = sample["subject"] || sample["category"]

    if subject in medical_subjects do
      %{
        id: get_id(sample),
        question: sample["question"],
        options: [
          "A. #{sample["A"]}",
          "B. #{sample["B"]}",
          "C. #{sample["C"]}",
          "D. #{sample["D"]}"
        ],
        answer: sample["answer"],
        subject: subject,
        meta: %{}
      }
    else
      nil
    end
  end

  @doc """
  Preprocess n2c2 medication extraction format.

  ## Output

      %{
        id: string,
        text: string,
        entities: [%{text: string, type: string, start: integer, end_pos: integer}],
        meta: map
      }

  """
  @spec n2c2_medication(map()) :: map()
  def n2c2_medication(sample) do
    %{
      id: get_id(sample),
      text: sample["text"],
      entities: normalize_entities(sample["entities"]),
      meta: %{
        document_id: sample["doc_id"]
      }
    }
  end

  @doc """
  Preprocess summarization format.

  ## Output

      %{
        id: string,
        source: string,
        target: string,
        meta: map
      }

  """
  @spec summarization(map()) :: map()
  def summarization(sample) do
    %{
      id: get_id(sample),
      source: sample["src"] || sample["source"] || sample["document"],
      target: sample["tgt"] || sample["target"] || sample["summary"],
      meta: %{
        document_id: sample["doc_id"],
        note_type: sample["note_type"]
      }
    }
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp get_id(sample) do
    sample["id"] || sample["uid"] || sample["idx"] ||
      :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp get_question(sample) do
    sample["question"] || sample["sent1"] || sample["prompt"]
  end

  defp normalize_options(sample) do
    cond do
      sample["options"] ->
        sample["options"]
        |> Enum.with_index()
        |> Enum.map(fn {opt, idx} -> "#{letter(idx)}. #{opt}" end)

      sample["choices"] ->
        sample["choices"]
        |> Enum.with_index()
        |> Enum.map(fn {opt, idx} -> "#{letter(idx)}. #{opt}" end)

      sample["opa"] ->
        [
          "A. #{sample["opa"]}",
          "B. #{sample["opb"]}",
          "C. #{sample["opc"]}",
          "D. #{sample["opd"]}"
        ]

      true ->
        []
    end
  end

  defp normalize_answer(sample) do
    cond do
      is_binary(sample["answer"]) and sample["answer"] in ~w(A B C D a b c d) ->
        String.upcase(sample["answer"])

      is_integer(sample["answer"]) ->
        letter(sample["answer"])

      is_integer(sample["cop"]) ->
        letter(sample["cop"])

      sample["answer_idx"] ->
        letter(sample["answer_idx"])

      true ->
        nil
    end
  end

  defp normalize_binary_answer(sample) do
    answer = sample["final_decision"] || sample["answer"] || sample["label"]

    cond do
      answer in ["yes", "Yes", "YES", 1, "1"] -> "yes"
      answer in ["no", "No", "NO", 0, "0"] -> "no"
      answer in ["maybe", "Maybe", "MAYBE", 2, "2"] -> "maybe"
      true -> answer
    end
  end

  defp extract_context(sample) do
    cond do
      sample["context"] -> sample["context"]
      sample["CONTEXTS"] -> Enum.join(sample["CONTEXTS"], "\n\n")
      sample["abstract"] -> sample["abstract"]
      true -> nil
    end
  end

  defp normalize_entities(entities) when is_list(entities) do
    Enum.map(entities, fn e ->
      %{
        text: e["text"] || e["mention"],
        type: e["type"] || e["label"],
        start: e["start"] || e["begin"],
        end_pos: e["end"]
      }
    end)
  end

  defp normalize_entities(_), do: []

  defp letter(0), do: "A"
  defp letter(1), do: "B"
  defp letter(2), do: "C"
  defp letter(3), do: "D"
  defp letter(n) when is_integer(n), do: <<65 + rem(n, 26)>>
end
