defmodule MedlumLlm.Datasets.Config do
  @moduledoc """
  Medical dataset configurations.

  Each configuration specifies:
  - HuggingFace repo ID
  - Preprocessing function
  - Default split and options
  - Dataset-specific metadata

  ## Dataset Schema

  Each dataset configuration includes:

    * `:name` - Display name
    * `:repo` - HuggingFace repository ID
    * `:hf_config` - HuggingFace dataset configuration (optional)
    * `:preprocessor` - Function reference for normalizing samples
    * `:revision` - Git revision to pin (nil = latest)
    * `:default_split` - Default split for evaluation
    * `:splits` - Available splits
    * `:task` - Task type (:mcq, :binary_qa, :reasoning, :ner, :summarization)
    * `:streaming` - Whether streaming is recommended for large datasets
    * `:requires_credentials` - Whether HuggingFace auth is needed
    * `:size` - Approximate sample counts by split
    * `:description` - Human-readable description
    * `:citation` - Citation reference

  ## Supported Datasets

  ### Medical Q&A
    * `:medqa` - USMLE-style medical MCQ (12K samples)
    * `:pubmedqa` - Binary QA from PubMed abstracts (1K labeled samples)
    * `:medmcqa` - Indian medical exam MCQ (187K samples)

  ### Reasoning
    * `:reasonmed` - Medical reasoning with chain-of-thought (1.1M samples)

  ### Benchmarks
    * `:mmlu_medical` - Medical subjects from MMLU benchmark (~3K samples)

  ### Clinical NLP
    * `:n2c2_medication` - Medication extraction from clinical notes
    * `:mimic_sum` - Clinical note summarization

  """

  alias MedlumLlm.Datasets.Preprocessor

  @type dataset_id :: atom()
  @type task_type :: :mcq | :binary_qa | :reasoning | :ner | :summarization

  @type config :: %{
          name: String.t(),
          repo: String.t(),
          hf_config: String.t() | nil,
          preprocessor: (map() -> map() | nil),
          revision: String.t() | nil,
          default_split: String.t(),
          splits: [String.t()],
          task: task_type(),
          streaming: boolean(),
          requires_credentials: boolean(),
          size: map(),
          description: String.t(),
          citation: String.t()
        }

  @datasets %{
    # =========================================================================
    # Medical Q&A Datasets
    # =========================================================================

    medqa: %{
      name: "MedQA",
      repo: "openlifescienceai/medqa",
      hf_config: nil,
      preprocessor: &Preprocessor.mcq/1,
      revision: nil,
      default_split: "test",
      splits: ["train", "dev", "test"],
      task: :mcq,
      streaming: false,
      requires_credentials: false,
      size: %{train: 10178, dev: 1272, test: 1273},
      description: "US Medical Licensing Exam questions",
      citation: "Jin et al., 2021",
      # Expected files for warmup (parquet format)
      files: ["data/test-00000-of-00001.parquet"]
    },

    pubmedqa: %{
      name: "PubMedQA",
      repo: "qiaojin/PubMedQA",
      hf_config: "pqa_labeled",
      preprocessor: &Preprocessor.binary_qa/1,
      revision: nil,
      default_split: "train",
      splits: ["train"],
      task: :binary_qa,
      streaming: false,
      requires_credentials: false,
      size: %{train: 1000},
      description: "Yes/No/Maybe questions from PubMed abstracts",
      citation: "Jin et al., 2019",
      files: ["pqa_labeled/train-00000-of-00001.parquet"]
    },

    medmcqa: %{
      name: "MedMCQA",
      repo: "openlifescienceai/medmcqa",
      hf_config: nil,
      preprocessor: &Preprocessor.mcq/1,
      revision: nil,
      default_split: "validation",
      splits: ["train", "validation"],
      task: :mcq,
      streaming: false,
      requires_credentials: false,
      size: %{train: 182_822, validation: 4183},
      description: "Indian medical entrance exam questions",
      citation: "Pal et al., 2022",
      files: ["data/test-00000-of-00001.parquet"]
    },

    # =========================================================================
    # Reasoning Datasets
    # =========================================================================

    reasonmed: %{
      name: "ReasonMed",
      repo: "FreedomIntelligence/medical-o1-reasoning-SFT",
      hf_config: nil,
      preprocessor: &Preprocessor.reasoning/1,
      revision: nil,
      default_split: "train",
      splits: ["train"],
      # 1.1M samples - MUST stream
      streaming: true,
      task: :reasoning,
      requires_credentials: false,
      size: %{train: 1_100_000},
      description: "Medical reasoning with chain-of-thought",
      citation: "FreedomIntelligence, 2024",
      files: []
    },

    # =========================================================================
    # MMLU Medical Subsets
    # =========================================================================

    mmlu_medical: %{
      name: "MMLU Medical",
      repo: "cais/mmlu",
      hf_config: "all",
      preprocessor: &Preprocessor.mmlu_medical/1,
      revision: nil,
      default_split: "test",
      splits: ["validation", "test"],
      task: :mcq,
      streaming: false,
      requires_credentials: false,
      size: %{validation: 1531, test: 3059},
      description: "Medical subjects from MMLU benchmark",
      citation: "Hendrycks et al., 2021",
      medical_subjects: [
        "anatomy",
        "clinical_knowledge",
        "college_biology",
        "college_medicine",
        "medical_genetics",
        "professional_medicine",
        "virology"
      ],
      files: []
    },

    # =========================================================================
    # Clinical NLP Datasets
    # =========================================================================

    n2c2_medication: %{
      name: "n2c2 Medication Extraction",
      repo: "bigbio/n2c2_2009",
      hf_config: nil,
      preprocessor: &Preprocessor.n2c2_medication/1,
      revision: nil,
      default_split: "test",
      splits: ["train", "test"],
      task: :ner,
      streaming: false,
      # Requires credentialing
      requires_credentials: true,
      size: %{train: 696, test: 251},
      description: "Medication extraction from clinical notes",
      citation: "Uzuner et al., 2010",
      files: []
    },

    # =========================================================================
    # Summarization Datasets
    # =========================================================================

    mimic_sum: %{
      name: "MIMIC Summarization",
      repo: "bigbio/mimic_iii_sum",
      hf_config: nil,
      preprocessor: &Preprocessor.summarization/1,
      revision: nil,
      default_split: "test",
      splits: ["train", "validation", "test"],
      task: :summarization,
      streaming: false,
      # Requires credentialing
      requires_credentials: true,
      size: %{train: 40_000, validation: 5000, test: 5000},
      description: "Clinical note summarization",
      citation: "MIMIC-III, PhysioNet",
      files: []
    }
  }

  @doc """
  Get dataset configuration by name.

  ## Examples

      {:ok, config} = MedlumLlm.Datasets.Config.get(:medqa)
      config.name
      #=> "MedQA"

      {:error, :not_found} = MedlumLlm.Datasets.Config.get(:unknown)

  """
  @spec get(dataset_id()) :: {:ok, map()} | {:error, :not_found}
  def get(name) when is_atom(name) do
    case Map.fetch(@datasets, name) do
      {:ok, config} -> {:ok, Map.put(config, :id, name)}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  List all available dataset names.

  ## Examples

      MedlumLlm.Datasets.Config.list()
      #=> [:medqa, :pubmedqa, :medmcqa, :reasonmed, :mmlu_medical, ...]

  """
  @spec list() :: [dataset_id()]
  def list, do: Map.keys(@datasets)

  @doc """
  Returns all dataset configurations.

  ## Examples

      MedlumLlm.Datasets.Config.all()
      #=> %{medqa: %{name: "MedQA", ...}, ...}

  """
  @spec all() :: %{dataset_id() => config()}
  def all, do: @datasets

  @doc """
  List datasets by task type.

  ## Examples

      MedlumLlm.Datasets.Config.by_task(:mcq)
      #=> [:medqa, :medmcqa, :mmlu_medical]

      MedlumLlm.Datasets.Config.by_task(:reasoning)
      #=> [:reasonmed]

  """
  @spec by_task(task_type()) :: [dataset_id()]
  def by_task(task) do
    @datasets
    |> Enum.filter(fn {_k, v} -> v.task == task end)
    |> Enum.map(fn {k, _v} -> k end)
  end

  @doc """
  Check if dataset requires credentials.

  ## Examples

      MedlumLlm.Datasets.Config.requires_credentials?(:medqa)
      #=> false

      MedlumLlm.Datasets.Config.requires_credentials?(:n2c2_medication)
      #=> true

  """
  @spec requires_credentials?(dataset_id()) :: boolean()
  def requires_credentials?(name) do
    case get(name) do
      {:ok, config} -> config[:requires_credentials] == true
      _ -> false
    end
  end

  @doc """
  Returns datasets that don't require credentials.

  These are safe for automated warmup without user authentication.

  ## Examples

      MedlumLlm.Datasets.Config.public_datasets()
      #=> [:medqa, :pubmedqa, :medmcqa, :reasonmed, :mmlu_medical]

  """
  @spec public_datasets() :: [dataset_id()]
  def public_datasets do
    @datasets
    |> Enum.filter(fn {_id, config} -> not config.requires_credentials end)
    |> Enum.map(fn {id, _config} -> id end)
  end

  @doc """
  Returns the files to download for a dataset's default split.

  Used by `HfWarmup` to determine what files to download.

  ## Examples

      {:ok, files} = MedlumLlm.Datasets.Config.files_for_split(:medqa)

  """
  @spec files_for_split(dataset_id(), String.t() | nil) :: {:ok, [String.t()]} | {:error, term()}
  def files_for_split(dataset_id, split \\ nil) do
    case get(dataset_id) do
      {:ok, config} ->
        _split = split || config.default_split
        files = Map.get(config, :files, [])
        {:ok, files}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get dataset information for display.

  Returns a map with human-readable information about the dataset.

  ## Examples

      MedlumLlm.Datasets.Config.describe(:medqa)
      #=> %{
      #     name: "MedQA",
      #     description: "US Medical Licensing Exam questions",
      #     task: :mcq,
      #     total_samples: 12723,
      #     ...
      #   }

  """
  @spec describe(dataset_id()) :: {:ok, map()} | {:error, :not_found}
  def describe(name) do
    case get(name) do
      {:ok, config} ->
        total_samples =
          config.size
          |> Map.values()
          |> Enum.sum()

        {:ok,
         %{
           name: config.name,
           description: config.description,
           task: config.task,
           splits: config.splits,
           default_split: config.default_split,
           total_samples: total_samples,
           streaming_recommended: config.streaming,
           requires_credentials: config.requires_credentials,
           citation: config.citation
         }}

      error ->
        error
    end
  end
end
