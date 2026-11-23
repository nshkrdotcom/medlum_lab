defmodule MedlumLlm.Eval.Benchmarks do
  @moduledoc """
  Medical benchmark configurations.

  These are config structs used with crucible_harness, NOT orchestration code.
  Each benchmark defines: dataset, split, prompts, metrics, and default models.

  ## Available Benchmarks

  ### MedQA Benchmarks
  - `medqa_zero_shot` - Zero-shot on USMLE questions
  - `medqa_few_shot` - 5-shot with training examples
  - `medqa_cot` - Chain-of-thought reasoning

  ### Other Benchmarks
  - `pubmedqa_zero_shot` - Yes/No/Maybe from PubMed
  - `medmcqa_zero_shot` - Indian medical entrance
  - `mmlu_medical_zero_shot` - Medical MMLU subjects
  - `cvl_hallucination` - CVL detection validation

  ## Usage

      {:ok, config} = MedlumLlm.Eval.Benchmarks.get(:medqa_zero_shot)
      # => %{name: "MedQA Zero-Shot", dataset: :medqa, ...}

      # List all benchmarks
      MedlumLlm.Eval.Benchmarks.list()
      #=> [:medqa_zero_shot, :medqa_few_shot, ...]

      # Filter by task type
      MedlumLlm.Eval.Benchmarks.by_task(:mcq)
      #=> [:medqa_zero_shot, :medqa_few_shot, :medmcqa_zero_shot, ...]
  """

  @benchmarks %{
    # =========================================================================
    # MedQA Benchmarks
    # =========================================================================

    medqa_zero_shot: %{
      name: "MedQA Zero-Shot",
      dataset: :medqa,
      split: "test",
      task: :mcq,
      prompt_template: :zero_shot_mcq,
      metrics: [:accuracy, :latency_p50, :latency_p95],
      default_models: [:biomistral_7b, :openbio_8b, :meditron_7b, :ii_medical_8b],
      timeout_ms: 60_000,
      description: "Zero-shot evaluation on USMLE-style questions"
    },

    medqa_few_shot: %{
      name: "MedQA 5-Shot",
      dataset: :medqa,
      split: "test",
      task: :mcq,
      prompt_template: :few_shot_mcq,
      few_shot: %{count: 5, source: :train, strategy: :random},
      metrics: [:accuracy, :latency_p50],
      default_models: [:openbio_8b, :ii_medical_8b, :huatuo_o1_8b],
      timeout_ms: 90_000,
      description: "5-shot evaluation with training examples"
    },

    medqa_cot: %{
      name: "MedQA Chain-of-Thought",
      dataset: :medqa,
      split: "test",
      task: :mcq_cot,
      prompt_template: :chain_of_thought_mcq,
      metrics: [:accuracy, :reasoning_quality, :latency_p50],
      default_models: [:huatuo_o1_8b, :openbio_8b],
      timeout_ms: 120_000,
      description: "Chain-of-thought reasoning evaluation"
    },

    # =========================================================================
    # PubMedQA Benchmarks
    # =========================================================================

    pubmedqa_zero_shot: %{
      name: "PubMedQA Zero-Shot",
      dataset: :pubmedqa,
      split: "test",
      task: :binary_qa,
      prompt_template: :zero_shot_binary_qa,
      metrics: [:accuracy, :f1_macro, :latency_p50],
      default_models: [:biomistral_7b, :openbio_8b, :meditron_7b],
      timeout_ms: 60_000,
      description: "Yes/No/Maybe questions from PubMed"
    },

    # =========================================================================
    # MedMCQA Benchmarks
    # =========================================================================

    medmcqa_zero_shot: %{
      name: "MedMCQA Zero-Shot",
      dataset: :medmcqa,
      split: "validation",  # Test labels not public
      task: :mcq,
      prompt_template: :zero_shot_mcq,
      metrics: [:accuracy, :latency_p50],
      default_models: [:biomistral_7b, :openbio_8b, :ii_medical_8b],
      timeout_ms: 60_000,
      description: "Indian medical entrance exam questions"
    },

    # =========================================================================
    # MMLU Medical Benchmarks
    # =========================================================================

    mmlu_medical_zero_shot: %{
      name: "MMLU Medical Zero-Shot",
      dataset: :mmlu_medical,
      split: "test",
      task: :mcq,
      prompt_template: :zero_shot_mcq,
      metrics: [:accuracy, :accuracy_by_subject, :latency_p50],
      default_models: [:openbio_8b, :ii_medical_8b],
      timeout_ms: 60_000,
      description: "Medical subjects from MMLU benchmark"
    },

    # =========================================================================
    # CVL Benchmarks
    # =========================================================================

    cvl_hallucination: %{
      name: "CVL Hallucination Detection",
      dataset: :medqa,
      split: "test",
      task: :cvl_verification,
      metrics: [:hallucination_recall, :hallucination_precision, :f1],
      default_models: [:ii_medical_8b],
      timeout_ms: 120_000,
      description: "Evaluate CVL hallucination detection on model errors"
    },

    # =========================================================================
    # Reasoning Benchmarks
    # =========================================================================

    reasonmed_sample: %{
      name: "ReasonMed Sample",
      dataset: :reasonmed,
      split: "train",
      streaming: true,
      default_limit: 1000,
      task: :reasoning,
      prompt_template: :reasoning_eval,
      metrics: [:accuracy, :reasoning_quality, :latency_p50],
      default_models: [:huatuo_o1_8b],
      timeout_ms: 180_000,
      description: "Reasoning quality evaluation on medical-o1 data"
    }
  }

  @doc """
  Get benchmark configuration by name.

  ## Examples

      {:ok, config} = MedlumLlm.Eval.Benchmarks.get(:medqa_zero_shot)
      config.name
      #=> "MedQA Zero-Shot"

      {:error, :not_found} = MedlumLlm.Eval.Benchmarks.get(:nonexistent)

  """
  @spec get(atom()) :: {:ok, map()} | {:error, :not_found}
  def get(name) do
    case Map.fetch(@benchmarks, name) do
      {:ok, config} -> {:ok, Map.put(config, :id, name)}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Get benchmark configuration by name, raising on error.

  ## Examples

      config = MedlumLlm.Eval.Benchmarks.get!(:medqa_zero_shot)
      config.name
      #=> "MedQA Zero-Shot"

  """
  @spec get!(atom()) :: map()
  def get!(name) do
    case get(name) do
      {:ok, config} -> config
      {:error, :not_found} -> raise ArgumentError, "Unknown benchmark: #{inspect(name)}"
    end
  end

  @doc """
  List all available benchmarks.

  ## Examples

      MedlumLlm.Eval.Benchmarks.list()
      #=> [:medqa_zero_shot, :medqa_few_shot, :medqa_cot, ...]

  """
  @spec list() :: [atom()]
  def list, do: Map.keys(@benchmarks)

  @doc """
  List benchmarks by task type.

  ## Task Types

  - `:mcq` - Multiple choice questions
  - `:mcq_cot` - MCQ with chain-of-thought
  - `:binary_qa` - Yes/No/Maybe questions
  - `:cvl_verification` - CVL hallucination detection
  - `:reasoning` - Reasoning evaluation

  ## Examples

      MedlumLlm.Eval.Benchmarks.by_task(:mcq)
      #=> [:medqa_zero_shot, :medqa_few_shot, :medmcqa_zero_shot, :mmlu_medical_zero_shot]

  """
  @spec by_task(atom()) :: [atom()]
  def by_task(task) do
    @benchmarks
    |> Enum.filter(fn {_k, v} -> v.task == task end)
    |> Enum.map(fn {k, _v} -> k end)
  end

  @doc """
  List benchmarks by dataset.

  ## Examples

      MedlumLlm.Eval.Benchmarks.by_dataset(:medqa)
      #=> [:medqa_zero_shot, :medqa_few_shot, :medqa_cot, :cvl_hallucination]

  """
  @spec by_dataset(atom()) :: [atom()]
  def by_dataset(dataset) do
    @benchmarks
    |> Enum.filter(fn {_k, v} -> v.dataset == dataset end)
    |> Enum.map(fn {k, _v} -> k end)
  end

  @doc """
  Get default models for a benchmark.

  ## Examples

      MedlumLlm.Eval.Benchmarks.default_models(:medqa_zero_shot)
      #=> [:biomistral_7b, :openbio_8b, :meditron_7b, :ii_medical_8b]

  """
  @spec default_models(atom()) :: [atom()]
  def default_models(name) do
    case get(name) do
      {:ok, config} -> config.default_models
      _ -> []
    end
  end

  @doc """
  Get all benchmarks as a map.

  ## Examples

      all = MedlumLlm.Eval.Benchmarks.all()
      all.medqa_zero_shot.name
      #=> "MedQA Zero-Shot"

  """
  @spec all() :: map()
  def all, do: @benchmarks

  @doc """
  Get benchmarks that include a specific metric.

  ## Examples

      MedlumLlm.Eval.Benchmarks.with_metric(:accuracy)
      #=> [:medqa_zero_shot, :medqa_few_shot, ...]

  """
  @spec with_metric(atom()) :: [atom()]
  def with_metric(metric) do
    @benchmarks
    |> Enum.filter(fn {_k, v} -> metric in v.metrics end)
    |> Enum.map(fn {k, _v} -> k end)
  end

  @doc """
  Get the prompt template for a benchmark.

  ## Examples

      MedlumLlm.Eval.Benchmarks.prompt_template(:medqa_zero_shot)
      #=> :zero_shot_mcq

  """
  @spec prompt_template(atom()) :: atom() | nil
  def prompt_template(name) do
    case get(name) do
      {:ok, config} -> Map.get(config, :prompt_template)
      _ -> nil
    end
  end

  @doc """
  Check if a benchmark supports streaming.

  ## Examples

      MedlumLlm.Eval.Benchmarks.streaming?(:reasonmed_sample)
      #=> true

      MedlumLlm.Eval.Benchmarks.streaming?(:medqa_zero_shot)
      #=> false

  """
  @spec streaming?(atom()) :: boolean()
  def streaming?(name) do
    case get(name) do
      {:ok, config} -> Map.get(config, :streaming, false)
      _ -> false
    end
  end

  @doc """
  Get benchmark timeout in milliseconds.

  ## Examples

      MedlumLlm.Eval.Benchmarks.timeout_ms(:medqa_zero_shot)
      #=> 60_000

  """
  @spec timeout_ms(atom()) :: integer() | nil
  def timeout_ms(name) do
    case get(name) do
      {:ok, config} -> config.timeout_ms
      _ -> nil
    end
  end
end
