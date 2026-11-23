defmodule MedlumLlm.Datasets do
  @moduledoc """
  Medical dataset configurations and loading.

  Thin wrapper around `hf_datasets_ex` for medical benchmarks. This module
  provides medical-specific dataset configurations and preprocessing while
  delegating dataset loading to the NSAI infrastructure.

  ## Usage

      # Load MedQA test split
      {:ok, dataset} = MedlumLlm.Datasets.load(:medqa)

      # Load with sampling
      {:ok, dataset} = MedlumLlm.Datasets.load(:medqa, sample: 100, seed: 42)

      # Stream large datasets
      {:ok, stream} = MedlumLlm.Datasets.load(:reasonmed, streaming: true)

      # List available datasets
      MedlumLlm.Datasets.available()
      #=> [:medqa, :pubmedqa, :medmcqa, :reasonmed, :mmlu_medical, ...]

  ## Normalized Sample Format

  All datasets are preprocessed to a common format:

      %{
        id: "medqa_001",
        question: "A 45-year-old man presents with...",
        options: ["A. ...", "B. ...", "C. ...", "D. ..."],
        answer: "A",
        explanation: "...",
        subject: "cardiology",
        meta: %{}
      }

  ## Supported Datasets

  | Dataset | Task | Size | Description |
  |---------|------|------|-------------|
  | `:medqa` | MCQ | 12K | USMLE-style questions |
  | `:pubmedqa` | Binary QA | 1K | PubMed abstracts |
  | `:medmcqa` | MCQ | 187K | Indian medical exams |
  | `:reasonmed` | Reasoning | 1.1M | Chain-of-thought |
  | `:mmlu_medical` | MCQ | ~3K | Medical MMLU subjects |
  | `:n2c2_medication` | NER | ~1K | Medication extraction |
  | `:mimic_sum` | Summarization | 50K | Clinical notes |

  ## Streaming Large Datasets

  ReasonMed has 1.1M samples. Always use streaming:

      {:ok, stream} = MedlumLlm.Datasets.load(:reasonmed,
        streaming: true,
        limit: 10_000
      )

      stream
      |> Stream.map(&process_sample/1)
      |> Stream.run()

  """

  alias MedlumLlm.Datasets.Config
  alias MedlumLlm.Integration.Error

  @type dataset_name :: atom()
  @type sample :: map()

  # Allow injection of HfDatasetsEx for testing
  @hf_datasets Application.compile_env(:medlum_llm, :hf_datasets_module, HfDatasetsEx)

  @doc """
  Load a medical dataset.

  ## Options

    * `:split` - Dataset split (default: from config)
    * `:sample` - Random sample size (requires full load, not for streaming)
    * `:limit` - Take first N samples (works with streaming)
    * `:seed` - Random seed for sampling (default: 42)
    * `:streaming` - Force streaming mode (default: from config)
    * `:revision` - Pin to specific commit (default: from config)

  ## Returns

  `{:ok, Enumerable.t()}` where the enumerable yields normalized samples.

  ## Examples

      # Load test split (default)
      {:ok, dataset} = MedlumLlm.Datasets.load(:medqa)

      # Load train split
      {:ok, dataset} = MedlumLlm.Datasets.load(:medqa, split: "train")

      # Random sample for development
      {:ok, dataset} = MedlumLlm.Datasets.load(:medqa, sample: 100, seed: 42)

      # Limit stream
      {:ok, stream} = MedlumLlm.Datasets.load(:reasonmed, streaming: true, limit: 1000)

  """
  @spec load(dataset_name(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def load(dataset_name, opts \\ []) do
    with {:ok, config} <- Config.get(dataset_name),
         opts <- merge_defaults(config, opts),
         {:ok, dataset} <- load_from_hf(config, opts) do
      preprocessed = apply_preprocessing(dataset, config, opts)
      {:ok, preprocessed}
    end
  end

  @doc """
  List available medical datasets.

  ## Examples

      MedlumLlm.Datasets.available()
      #=> [:medqa, :pubmedqa, :medmcqa, :reasonmed, :mmlu_medical, :n2c2_medication, :mimic_sum]

  """
  @spec available() :: [dataset_name()]
  def available, do: Config.list()

  @doc """
  Get information about a dataset.

  ## Examples

      {:ok, info} = MedlumLlm.Datasets.info(:medqa)
      info.name
      #=> "MedQA"

  """
  @spec info(dataset_name()) :: {:ok, map()} | {:error, :not_found}
  def info(dataset_name), do: Config.get(dataset_name)

  @doc """
  Get human-readable description of a dataset.

  ## Examples

      {:ok, desc} = MedlumLlm.Datasets.describe(:medqa)
      desc.total_samples
      #=> 12723

  """
  @spec describe(dataset_name()) :: {:ok, map()} | {:error, :not_found}
  def describe(dataset_name), do: Config.describe(dataset_name)

  @doc """
  Load all splits of a dataset (train, validation, test).

  Returns a map of split name to dataset enumerable.

  ## Examples

      {:ok, splits} = MedlumLlm.Datasets.load_all_splits(:medqa)
      splits["train"]  # Training dataset
      splits["test"]   # Test dataset

  """
  @spec load_all_splits(dataset_name(), keyword()) ::
          {:ok, %{String.t() => Enumerable.t()}} | {:error, term()}
  def load_all_splits(dataset_name, opts \\ []) do
    with {:ok, config} <- Config.get(dataset_name) do
      splits = config[:splits] || ["train", "validation", "test"]

      results =
        splits
        |> Enum.map(fn split ->
          case load(dataset_name, Keyword.put(opts, :split, split)) do
            {:ok, ds} -> {split, ds}
            {:error, _} -> {split, nil}
          end
        end)
        |> Enum.reject(fn {_, ds} -> is_nil(ds) end)
        |> Map.new()

      {:ok, results}
    end
  end

  @doc """
  List datasets by task type.

  ## Examples

      MedlumLlm.Datasets.by_task(:mcq)
      #=> [:medqa, :medmcqa, :mmlu_medical]

      MedlumLlm.Datasets.by_task(:reasoning)
      #=> [:reasonmed]

  """
  @spec by_task(atom()) :: [dataset_name()]
  def by_task(task), do: Config.by_task(task)

  @doc """
  Check if a dataset requires HuggingFace credentials.

  ## Examples

      MedlumLlm.Datasets.requires_credentials?(:medqa)
      #=> false

      MedlumLlm.Datasets.requires_credentials?(:n2c2_medication)
      #=> true

  """
  @spec requires_credentials?(dataset_name()) :: boolean()
  def requires_credentials?(dataset_name), do: Config.requires_credentials?(dataset_name)

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp merge_defaults(config, opts) do
    opts
    |> Keyword.put_new(:split, config[:default_split] || "test")
    |> Keyword.put_new(:seed, 42)
    |> Keyword.put_new(:streaming, config[:streaming] || false)
    |> Keyword.put_new(:revision, config[:revision])
  end

  defp load_from_hf(config, opts) do
    hf_opts =
      [
        split: opts[:split],
        streaming: opts[:streaming]
      ]
      |> maybe_add(:config, config[:hf_config])
      |> maybe_add(:revision, opts[:revision])

    case apply(@hf_datasets, :load_dataset, [config.repo, hf_opts]) do
      {:ok, dataset} ->
        {:ok, dataset}

      {:error, reason} ->
        {:error,
         %Error{
           library: :hf_datasets_ex,
           operation: :load_dataset,
           reason: reason,
           context: %{dataset: config.repo, opts: hf_opts}
         }}
    end
  end

  defp apply_preprocessing(dataset, config, opts) do
    dataset
    |> Stream.map(config.preprocessor)
    # Filter out nil from mmlu_medical
    |> Stream.reject(&is_nil/1)
    |> maybe_sample(opts[:sample], opts[:seed])
    |> maybe_limit(opts[:limit])
  end

  defp maybe_sample(dataset, nil, _seed), do: dataset

  defp maybe_sample(dataset, n, seed) do
    :rand.seed(:exsss, {seed, seed, seed})

    dataset
    |> Enum.to_list()
    |> Enum.shuffle()
    |> Enum.take(n)
  end

  defp maybe_limit(dataset, nil), do: dataset
  defp maybe_limit(dataset, n), do: Stream.take(dataset, n)

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end
