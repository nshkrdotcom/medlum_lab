defmodule MedlumLlm.Router do
  @moduledoc """
  Task-based model routing for medical NLP tasks.

  Routes tasks to optimal models based on task requirements, available hardware,
  and current profile configuration.

  ## Usage

      # Get routing config for a task
      {:ok, config} = Router.route(:quick_summary)

      # Execute a task with automatic model selection
      {:ok, result} = Router.execute(:medication_extraction, text)

  ## Available Tasks

  ### Text Generation
  - `:quick_summary` - Fast summarization, lower accuracy acceptable
  - `:detailed_summary` - Balanced summarization
  - `:critical_analysis` - Highest accuracy, for clinical decisions

  ### Verification
  - `:hallucination_check` - Detect fabricated information

  ### Entity Extraction
  - `:medication_extraction` - Extract drug names, doses, frequencies
  - `:disease_extraction` - Extract conditions, diagnoses
  - `:lab_extraction` - Extract lab values, tests
  - `:anatomy_extraction` - Extract body parts, anatomical terms

  ### De-identification
  - `:batch_pii` - High accuracy PII detection for batch processing
  - `:realtime_pii` - Fast PII detection for interactive use

  ### Embedding
  - `:document_search` - Document-level semantic search
  - `:sentence_similarity` - Sentence-level comparison

  """

  alias MedlumLlm.Models.Registry

  @type task :: atom()
  @type route_config :: %{
          model: atom(),
          category: atom(),
          tier: atom(),
          domain: atom() | nil,
          provider: atom(),
          timeout: integer()
        }

  # Task definitions with routing parameters
  @tasks %{
    # Text Generation Tasks
    quick_summary: %{
      name: :quick_summary,
      description: "Fast text summarization for quick review",
      category: :chat,
      tier: :fast,
      default_timeout: 30_000
    },
    detailed_summary: %{
      name: :detailed_summary,
      description: "Balanced summarization with moderate accuracy",
      category: :chat,
      tier: :balanced,
      default_timeout: 60_000
    },
    critical_analysis: %{
      name: :critical_analysis,
      description: "High-accuracy analysis for clinical decisions",
      category: :chat,
      tier: :accurate,
      default_timeout: 300_000
    },

    # Verification Tasks
    hallucination_check: %{
      name: :hallucination_check,
      description: "Detect fabricated or unsupported claims",
      category: :chat,
      tier: :accurate,
      default_timeout: 120_000
    },

    # Entity Extraction Tasks
    medication_extraction: %{
      name: :medication_extraction,
      description: "Extract medications, dosages, and frequencies",
      category: :ner,
      domain: :pharma,
      tier: :balanced,
      default_timeout: 10_000
    },
    disease_extraction: %{
      name: :disease_extraction,
      description: "Extract diseases, conditions, and diagnoses",
      category: :ner,
      domain: :disease,
      tier: :balanced,
      default_timeout: 10_000
    },
    lab_extraction: %{
      name: :lab_extraction,
      description: "Extract lab tests, values, and reference ranges",
      category: :ner,
      domain: :chemical,
      tier: :balanced,
      default_timeout: 10_000
    },
    anatomy_extraction: %{
      name: :anatomy_extraction,
      description: "Extract anatomical terms and body parts",
      category: :ner,
      domain: :anatomy,
      tier: :fast,
      default_timeout: 10_000
    },

    # PII Detection Tasks
    batch_pii: %{
      name: :batch_pii,
      description: "High-accuracy PII detection for batch processing",
      category: :pii,
      tier: :accurate,
      default_timeout: 30_000
    },
    realtime_pii: %{
      name: :realtime_pii,
      description: "Fast PII detection for real-time use",
      category: :pii,
      tier: :fast,
      default_timeout: 5_000
    },

    # Embedding Tasks
    document_search: %{
      name: :document_search,
      description: "Semantic search over document corpus",
      category: :embed,
      tier: :balanced,
      default_timeout: 10_000
    },
    sentence_similarity: %{
      name: :sentence_similarity,
      description: "Compare semantic similarity of sentences",
      category: :embed,
      tier: :balanced,
      default_timeout: 5_000
    }
  }

  # Fallback chains for when primary model unavailable
  @fallback_chains %{
    critical_analysis: [:med42_70b, :openbio_70b, :ii_medical_8b, :openbio_8b],
    detailed_summary: [:ii_medical_8b, :openbio_8b, :biomistral_7b],
    quick_summary: [:biomistral_7b, :meditron_7b, :openbio_8b],
    hallucination_check: [:med42_70b, :ii_medical_8b, :openbio_8b],
    medication_extraction: [
      :openmed_pharma_superclinical,
      :openmed_pharma_zeroshot
    ],
    disease_extraction: [
      :openmed_disease_superclinical,
      :openmed_disease_zeroshot
    ],
    lab_extraction: [:openmed_chemical_bigmed],
    batch_pii: [:openmed_pii_large, :openmed_pii_base],
    realtime_pii: [:openmed_pii_small, :openmed_pii_base],
    document_search: [:nomic_embed, :mxbai_embed],
    sentence_similarity: [:nomic_embed, :mxbai_embed]
  }

  # ==========================================================================
  # Public API
  # ==========================================================================

  @doc """
  Routes a task to the optimal model configuration.

  ## Options

  - `:tier` - Override the default tier for this task
  - `:timeout` - Override the default timeout (milliseconds)
  - `:model` - Specify a particular model to use

  ## Returns

  `{:ok, config}` where config is a map containing:
  - `:model` - The model atom to use
  - `:category` - The model category
  - `:tier` - The model tier
  - `:domain` - The domain (for NER tasks)
  - `:provider` - The provider (:ollama, :huggingface)
  - `:timeout` - Timeout in milliseconds

  """
  @spec route(task(), keyword()) :: {:ok, route_config()} | {:error, :unknown_task}
  def route(task, opts \\ []) do
    case Map.get(@tasks, task) do
      nil ->
        {:error, :unknown_task}

      task_def ->
        tier = Keyword.get(opts, :tier, task_def.tier)
        timeout = Keyword.get(opts, :timeout, task_def.default_timeout)
        override_model = Keyword.get(opts, :model)

        # Find the best model for this task
        model =
          if override_model do
            case Registry.get(override_model) do
              {:ok, m} -> m
              _ -> find_model(task_def, tier)
            end
          else
            find_model(task_def, tier)
          end

        config = %{
          model: model.id,
          category: model.category,
          tier: model.tier,
          domain: Map.get(task_def, :domain),
          provider: model.provider,
          timeout: timeout
        }

        {:ok, config}
    end
  end

  @doc """
  Returns the fallback model chain for a task.

  Used when the primary model is unavailable.
  """
  @spec get_fallbacks(task()) :: [atom()]
  def get_fallbacks(task) do
    Map.get(@fallback_chains, task, [])
  end

  @doc """
  Returns a list of all available tasks.
  """
  @spec available_tasks() :: [task()]
  def available_tasks do
    Map.keys(@tasks)
  end

  @doc """
  Returns information about a specific task.
  """
  @spec task_info(task()) :: {:ok, map()} | {:error, :unknown_task}
  def task_info(task) do
    case Map.get(@tasks, task) do
      nil -> {:error, :unknown_task}
      info -> {:ok, info}
    end
  end

  @doc """
  Execute a task with automatic model selection.

  This is a convenience wrapper that routes the task and dispatches
  to the appropriate provider.
  """
  @spec execute(task(), String.t() | [String.t()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def execute(task, input, opts \\ []) do
    with {:ok, config} <- route(task, opts) do
      dispatch(config, input, opts)
    end
  end

  # ==========================================================================
  # Private Functions
  # ==========================================================================

  defp find_model(task_def, tier) do
    category = task_def.category
    domain = Map.get(task_def, :domain)

    models =
      Registry.by_category(category, domain: domain)
      |> Enum.filter(fn model -> model.tier == tier end)

    case models do
      [model | _] ->
        model

      [] ->
        # Fall back to any model in category
        [model | _] = Registry.by_category(category, domain: domain)
        model
    end
  end

  defp dispatch(config, input, opts) do
    case config.category do
      :chat ->
        dispatch_chat(config, input, opts)

      :embed ->
        dispatch_embed(config, input, opts)

      :ner ->
        dispatch_ner(config, input, opts)

      :pii ->
        dispatch_pii(config, input, opts)
    end
  end

  defp dispatch_chat(config, input, opts) do
    model = config.model
    timeout = config.timeout

    case config.provider do
      :ollama ->
        MedlumLlm.Chat.chat(input, Keyword.merge(opts, model: model, timeout: timeout))

      :mock ->
        MedlumLlm.Provider.Mock.generate(model, input, opts)

      _ ->
        {:error, :unsupported_provider}
    end
  end

  defp dispatch_embed(config, input, opts) do
    model = config.model

    case config.provider do
      :ollama ->
        if is_list(input) do
          MedlumLlm.Embedder.embed_batch(input, Keyword.merge(opts, model: model))
        else
          MedlumLlm.Embedder.embed(input, Keyword.merge(opts, model: model))
        end

      :mock ->
        texts = if is_list(input), do: input, else: [input]
        MedlumLlm.Provider.Mock.embed(model, texts, opts)

      _ ->
        {:error, :unsupported_provider}
    end
  end

  defp dispatch_ner(config, input, opts) do
    model = config.model

    case config.provider do
      :huggingface ->
        # Would use Snakebridge in real implementation
        {:error, :huggingface_not_configured}

      :mock ->
        MedlumLlm.Provider.Mock.extract_entities(model, input, opts)

      _ ->
        {:error, :unsupported_provider}
    end
  end

  defp dispatch_pii(config, input, opts) do
    model = config.model

    case config.provider do
      :huggingface ->
        # Would use Snakebridge in real implementation
        {:error, :huggingface_not_configured}

      :mock ->
        MedlumLlm.Provider.Mock.extract_entities(model, input, opts)

      _ ->
        {:error, :unsupported_provider}
    end
  end
end
