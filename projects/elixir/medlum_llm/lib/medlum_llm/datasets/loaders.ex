defmodule MedlumLlm.Datasets.Loaders do
  @moduledoc """
  Medical dataset loaders that wrap HfDatasetsEx with DatasetsEx features.

  Provides seamless loading of medical datasets from HuggingFace Hub with:
  - Full lineage tracking via LineageIR artifact references
  - Medical-specific metadata (domain, clinical area, PHI status, etc.)
  - Versioning and reproducibility
  - Quality validation hooks

  ## Supported Datasets

  ### MCQ (Multiple Choice QA)
  - `:medqa` - MedQA USMLE-style questions
  - `:medmcqa` - Indian medical entrance exam questions
  - `:mmlu_clinical` - MMLU clinical knowledge subset
  - `:mmlu_medical_genetics` - MMLU medical genetics subset
  - `:mmlu_professional_medicine` - MMLU professional medicine subset

  ### Binary QA
  - `:pubmedqa` - PubMed research question answering

  ### Reasoning
  - `:medical_o1` - Medical chain-of-thought reasoning

  ### NER
  - `:ncbi_disease` - NCBI disease entity recognition

  ## Examples

      # Load MedQA with lineage tracking
      {:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa)

      # Load with options
      {:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa,
        split: "test",
        limit: 100,
        streaming: false
      )

      # Get artifact reference for lineage
      ref = DatasetsEx.artifact_ref(dataset)
  """

  alias DatasetsEx.Dataset
  alias MedlumLlm.Datasets.Metadata

  @type dataset_name ::
          :medqa
          | :medmcqa
          | :pubmedqa
          | :mmlu_clinical
          | :mmlu_medical_genetics
          | :mmlu_professional_medicine
          | :medical_o1
          | :ncbi_disease

  @medical_datasets %{
    medqa: %{
      repo_id: "bigbio/med_qa",
      config: "med_qa_en_source",
      default_split: "test",
      clinical_area: "usmle",
      task: :mcq,
      data_license: "MIT",
      phi_status: :none,
      access_level: :public,
      baselines: %{
        "GPT-4" => 86.1,
        "Med-PaLM 2" => 86.5,
        "BioMistral-7B" => 61.0
      },
      preprocessor: :preprocess_medqa
    },
    medmcqa: %{
      repo_id: "medmcqa/medmcqa",
      config: "default",
      default_split: "validation",
      clinical_area: "general_medicine",
      task: :mcq,
      data_license: "Apache-2.0",
      phi_status: :none,
      access_level: :public,
      baselines: %{
        "GPT-4" => 72.3,
        "PubMedBERT" => 40.5
      },
      preprocessor: :preprocess_medmcqa
    },
    pubmedqa: %{
      repo_id: "bigbio/pubmed_qa",
      config: "pubmed_qa_labeled_fold0_source",
      default_split: "test",
      clinical_area: "biomedical_research",
      task: :binary_qa,
      data_license: "MIT",
      phi_status: :none,
      access_level: :public,
      baselines: %{
        "GPT-4" => 75.2,
        "BioGPT" => 72.4
      },
      preprocessor: :preprocess_pubmedqa
    },
    mmlu_clinical: %{
      repo_id: "cais/mmlu",
      config: "clinical_knowledge",
      default_split: "test",
      clinical_area: "clinical_knowledge",
      task: :mcq,
      data_license: "MIT",
      phi_status: :none,
      access_level: :public,
      baselines: %{
        "GPT-4" => 86.0,
        "Claude-3" => 83.1
      },
      preprocessor: :preprocess_mmlu
    },
    mmlu_medical_genetics: %{
      repo_id: "cais/mmlu",
      config: "medical_genetics",
      default_split: "test",
      clinical_area: "medical_genetics",
      task: :mcq,
      data_license: "MIT",
      phi_status: :none,
      access_level: :public,
      baselines: %{
        "GPT-4" => 91.0
      },
      preprocessor: :preprocess_mmlu
    },
    mmlu_professional_medicine: %{
      repo_id: "cais/mmlu",
      config: "professional_medicine",
      default_split: "test",
      clinical_area: "professional_medicine",
      task: :mcq,
      data_license: "MIT",
      phi_status: :none,
      access_level: :public,
      baselines: %{
        "GPT-4" => 93.0
      },
      preprocessor: :preprocess_mmlu
    },
    medical_o1: %{
      repo_id: "FreedomIntelligence/medical-o1-reasoning-SFT",
      config: "default",
      default_split: "train",
      clinical_area: "reasoning",
      task: :reasoning,
      data_license: "Apache-2.0",
      phi_status: :none,
      access_level: :public,
      baselines: nil,
      preprocessor: :preprocess_reasoning
    },
    ncbi_disease: %{
      repo_id: "bigbio/ncbi_disease",
      config: "ncbi_disease_source",
      default_split: "test",
      clinical_area: "biomedical_ner",
      task: :ner,
      data_license: "CC0-1.0",
      phi_status: :none,
      access_level: :public,
      baselines: %{
        "PubMedBERT" => 87.8
      },
      preprocessor: :preprocess_ner
    }
  }

  @doc """
  Load a medical dataset with lineage tracking.

  ## Options
    - `:split` - Dataset split (default: from config)
    - `:limit` - Limit samples
    - `:streaming` - Use streaming mode (default: false)
    - `:revision` - Pin dataset revision for reproducibility
    - `:cache` - Use cache (default: true)

  ## Returns
  DatasetsEx.Dataset with medical metadata and lineage info.

  ## Examples

      {:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa)
      {:ok, dataset} = MedlumLlm.Datasets.Loaders.load(:medqa, split: "test", limit: 100)
  """
  @spec load(dataset_name(), keyword()) :: {:ok, Dataset.t()} | {:error, term()}
  def load(dataset_name, opts \\ []) when is_atom(dataset_name) do
    case Map.get(@medical_datasets, dataset_name) do
      nil ->
        {:error, {:unknown_medical_dataset, dataset_name}}

      config ->
        do_load(dataset_name, config, opts)
    end
  end

  @doc """
  List all available medical datasets.

  ## Examples

      MedlumLlm.Datasets.Loaders.list_datasets()
      # => [:medqa, :medmcqa, :pubmedqa, ...]
  """
  @spec list_datasets() :: [dataset_name()]
  def list_datasets do
    Map.keys(@medical_datasets)
  end

  @doc """
  Get metadata configuration for a medical dataset.

  ## Examples

      config = MedlumLlm.Datasets.Loaders.get_config(:medqa)
      config.clinical_area
      # => "usmle"
  """
  @spec get_config(dataset_name()) :: map() | nil
  def get_config(dataset_name) when is_atom(dataset_name) do
    Map.get(@medical_datasets, dataset_name)
  end

  @doc """
  List medical datasets by task type.

  ## Examples

      MedlumLlm.Datasets.Loaders.list_by_task(:mcq)
      # => [:medqa, :medmcqa, :mmlu_clinical, ...]
  """
  @spec list_by_task(:mcq | :binary_qa | :reasoning | :ner | :cvl) :: [dataset_name()]
  def list_by_task(task) when is_atom(task) do
    @medical_datasets
    |> Enum.filter(fn {_name, config} -> config.task == task end)
    |> Enum.map(fn {name, _config} -> name end)
  end

  @doc """
  List medical datasets by clinical area.

  ## Examples

      MedlumLlm.Datasets.Loaders.list_by_clinical_area("usmle")
      # => [:medqa]
  """
  @spec list_by_clinical_area(String.t()) :: [dataset_name()]
  def list_by_clinical_area(area) when is_binary(area) do
    @medical_datasets
    |> Enum.filter(fn {_name, config} -> config.clinical_area == area end)
    |> Enum.map(fn {name, _config} -> name end)
  end

  # Private implementation

  defp do_load(dataset_name, config, opts) do
    split = Keyword.get(opts, :split, config.default_split)
    limit = Keyword.get(opts, :limit)
    revision = Keyword.get(opts, :revision)
    cache = Keyword.get(opts, :cache, true)
    streaming = Keyword.get(opts, :streaming, false)

    hf_opts =
      [
        config: config.config,
        split: split,
        streaming: streaming
      ]
      |> maybe_add_opt(:revision, revision)
      |> maybe_add_opt(:token, Keyword.get(opts, :token))

    with {:ok, hf_dataset} <- load_from_hf(config.repo_id, hf_opts, cache),
         items <- preprocess_items(hf_dataset, config.preprocessor),
         items <- maybe_limit(items, limit) do
      dataset =
        Dataset.new(to_string(dataset_name),
          data: items,
          schema: task_to_schema(config.task),
          metadata:
            Metadata.build(config, %{
              hf_repo: config.repo_id,
              hf_revision: revision,
              hf_split: split,
              loaded_at: DateTime.utc_now(),
              sample_count: length(items)
            }),
          artifact_id: Ecto.UUID.generate()
        )

      {:ok, dataset}
    end
  end

  defp load_from_hf(repo_id, opts, cache) do
    # Try to use HfDatasetsEx if available
    if Code.ensure_loaded?(HfDatasetsEx) do
      apply(HfDatasetsEx, :load_dataset, [repo_id, Keyword.put(opts, :cache, cache)])
    else
      # Fallback to mock data for testing
      {:ok, mock_hf_dataset(repo_id, opts)}
    end
  end

  defp mock_hf_dataset(_repo_id, _opts) do
    # Returns a minimal mock structure for testing when HfDatasetsEx isn't available
    %{items: []}
  end

  defp preprocess_items(%{items: items}, preprocessor) when is_list(items) do
    Enum.map(items, &apply_preprocessor(&1, preprocessor))
  end

  defp preprocess_items(hf_dataset, preprocessor) when is_struct(hf_dataset) do
    items = Map.get(hf_dataset, :items, [])
    Enum.map(items, &apply_preprocessor(&1, preprocessor))
  end

  defp preprocess_items(items, preprocessor) when is_list(items) do
    Enum.map(items, &apply_preprocessor(&1, preprocessor))
  end

  defp preprocess_items(_, _preprocessor), do: []

  defp apply_preprocessor(item, :preprocess_medqa), do: preprocess_medqa(item)
  defp apply_preprocessor(item, :preprocess_medmcqa), do: preprocess_medmcqa(item)
  defp apply_preprocessor(item, :preprocess_pubmedqa), do: preprocess_pubmedqa(item)
  defp apply_preprocessor(item, :preprocess_mmlu), do: preprocess_mmlu(item)
  defp apply_preprocessor(item, :preprocess_reasoning), do: preprocess_reasoning(item)
  defp apply_preprocessor(item, :preprocess_ner), do: preprocess_ner(item)
  defp apply_preprocessor(item, _), do: item

  # MCQ Preprocessors

  defp preprocess_medqa(item) do
    %{
      id: get_id(item),
      question: get_field(item, [:question, "question"]),
      options: extract_options(item, [:options, "options", :answer_idx]),
      correct_answer: extract_correct_answer(item),
      subject: get_field(item, [:subject, "meta_info", :meta_info], "usmle"),
      explanation: get_field(item, [:explanation, "exp"])
    }
  end

  defp preprocess_medmcqa(item) do
    options = [
      get_field(item, [:opa, "opa"]),
      get_field(item, [:opb, "opb"]),
      get_field(item, [:opc, "opc"]),
      get_field(item, [:opd, "opd"])
    ]

    correct_idx = get_field(item, [:cop, "cop"], 0)
    correct_letter = Enum.at(["A", "B", "C", "D"], correct_idx, "A")

    %{
      id: get_id(item),
      question: get_field(item, [:question, "question"]),
      options: options,
      correct_answer: correct_letter,
      subject: get_field(item, [:subject_name, "subject_name"], "general"),
      explanation: get_field(item, [:exp, "exp"])
    }
  end

  defp preprocess_mmlu(item) do
    # MMLU format: question, choices (list), answer (index 0-3)
    choices = get_field(item, [:choices, "choices"], [])
    answer_idx = get_field(item, [:answer, "answer"], 0)
    correct_letter = Enum.at(["A", "B", "C", "D"], answer_idx, "A")

    %{
      id: get_id(item),
      question: get_field(item, [:question, "question"]),
      options: choices,
      correct_answer: correct_letter,
      subject: get_field(item, [:subject, "subject"], "clinical_knowledge"),
      explanation: nil
    }
  end

  # Binary QA Preprocessor

  defp preprocess_pubmedqa(item) do
    context_list = get_field(item, [:context, "context", :contexts, "contexts"], [])

    context =
      cond do
        is_list(context_list) -> Enum.join(context_list, " ")
        is_binary(context_list) -> context_list
        true -> ""
      end

    raw_answer = get_field(item, [:final_decision, "final_decision", :answer, "answer"])

    answer =
      case raw_answer do
        "yes" -> "yes"
        "no" -> "no"
        "maybe" -> "maybe"
        _ -> "maybe"
      end

    %{
      id: get_id(item),
      question: get_field(item, [:question, "question"]),
      context: context,
      answer: answer,
      explanation: get_field(item, [:long_answer, "long_answer"])
    }
  end

  # Reasoning Preprocessor

  defp preprocess_reasoning(item) do
    %{
      id: get_id(item),
      question: get_field(item, [:question, "question", :input, "input"]),
      thinking: get_field(item, [:thinking, "thinking", :thought, "thought"]),
      answer: get_field(item, [:answer, "answer", :output, "output"]),
      subject: get_field(item, [:subject, "subject"], "medical_reasoning")
    }
  end

  # NER Preprocessor

  defp preprocess_ner(item) do
    text = get_field(item, [:text, "text", :passage, "passage"], "")

    entities =
      get_field(item, [:entities, "entities", :mentions, "mentions"], [])
      |> Enum.map(fn entity ->
        %{
          text: get_field(entity, [:text, "text"]),
          type: get_field(entity, [:type, "type", :entity_type, "entity_type"], "DISEASE"),
          start: get_field(entity, [:start, "start", :offsets, "offsets"], 0) |> normalize_offset(),
          end_pos:
            get_field(entity, [:end, "end", :offsets, "offsets"], 0) |> normalize_offset(:end)
        }
      end)

    %{
      id: get_id(item),
      text: text,
      entities: entities
    }
  end

  # Helper functions

  defp get_id(item) do
    case get_field(item, [:id, "id", :idx, "idx"]) do
      nil -> Ecto.UUID.generate()
      id -> to_string(id)
    end
  end

  defp get_field(item, keys, default \\ nil)

  defp get_field(item, keys, default) when is_map(item) do
    Enum.find_value(keys, default, fn key ->
      case Map.get(item, key) do
        nil -> nil
        value -> value
      end
    end)
  end

  defp get_field(_item, _keys, default), do: default

  defp extract_options(item, keys) do
    options = get_field(item, keys, [])

    cond do
      is_list(options) and length(options) >= 4 ->
        Enum.take(options, 4)

      is_map(options) ->
        [
          Map.get(options, "A", Map.get(options, :A, "")),
          Map.get(options, "B", Map.get(options, :B, "")),
          Map.get(options, "C", Map.get(options, :C, "")),
          Map.get(options, "D", Map.get(options, :D, ""))
        ]

      true ->
        ["", "", "", ""]
    end
  end

  defp extract_correct_answer(item) do
    answer = get_field(item, [:answer, "answer", :answer_idx, "answer_idx", :cop, "cop"])

    cond do
      answer in ["A", "B", "C", "D"] -> answer
      answer in [0, 1, 2, 3] -> Enum.at(["A", "B", "C", "D"], answer)
      is_binary(answer) and String.length(answer) == 1 -> String.upcase(answer)
      true -> "A"
    end
  end

  defp normalize_offset(value, position \\ :start)

  defp normalize_offset(offset, _position) when is_integer(offset), do: offset

  defp normalize_offset([start, _end_val], :start), do: start
  defp normalize_offset([_start, end_val], :end), do: end_val
  defp normalize_offset(_, _), do: 0

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit) when is_integer(limit), do: Enum.take(items, limit)

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp task_to_schema(:mcq), do: :medical_mcq
  defp task_to_schema(:binary_qa), do: :medical_binary_qa
  defp task_to_schema(:reasoning), do: :medical_reasoning
  defp task_to_schema(:ner), do: :medical_ner
  defp task_to_schema(:cvl), do: :medical_cvl
  defp task_to_schema(_), do: :medical
end
