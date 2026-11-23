defmodule MedlumLlm do
  @moduledoc """
  Medical LLM library for Elixir using Ollama/Ollixir.

  MedlumLlm provides a unified interface to medical-domain language models
  for text generation, embeddings, and clinical NLP tasks.

  ## Supported Models

  ### Text Generation (via Ollama)

  | Model | Size | Use Case |
  |-------|------|----------|
  | BioMistral-7B | ~4GB VRAM | Medical Q&A, clinical text |
  | OpenBioLLM-8B | ~5GB VRAM | Medical reasoning, diagnosis |
  | Meditron-7B | ~4GB VRAM | Medical literature, evidence |

  ### Embeddings (via Ollama)

  | Model | Dimensions | Use Case |
  |-------|------------|----------|
  | nomic-embed-text | 768 | General clinical embeddings |
  | mxbai-embed-large | 1024 | High-quality medical embeddings |

  ## Quick Start

      # Text generation with medical LLMs
      {:ok, response} = MedlumLlm.chat("What are the symptoms of myocardial infarction?")

      # Clinical embeddings
      {:ok, embedding} = MedlumLlm.embed("acute chest pain radiating to left arm")

      # Semantic similarity
      {:ok, similarity} = MedlumLlm.similarity("heart attack", "myocardial infarction")

  ## Configuration

      config :medlum_llm,
        ollama_host: "http://localhost:11434",
        chat_model: "hf.co/BioMistral/BioMistral-7B-GGUF",
        embed_model: "nomic-embed-text"

  """

  alias MedlumLlm.{Chat, Embedder, Models}

  # =============================================================================
  # Chat / Text Generation API
  # =============================================================================

  @doc """
  Send a message to a medical LLM and get a response.

  ## Options

    * `:model` - Model to use (default: configured chat_model)
    * `:system` - System prompt for medical context
    * `:temperature` - Sampling temperature (0.0-1.0)
    * `:max_tokens` - Maximum tokens in response
    * `:stream` - Stream responses (default: false)

  ## Examples

      # Simple query
      {:ok, response} = MedlumLlm.chat("What is hypertension?")

      # With system prompt
      {:ok, response} = MedlumLlm.chat(
        "Explain the pathophysiology",
        system: "You are a cardiology specialist."
      )

      # Using specific model
      {:ok, response} = MedlumLlm.chat(
        "Summarize this clinical note",
        model: :biomistral_7b
      )

  """
  @spec chat(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defdelegate chat(message, opts \\ []), to: Chat

  @doc """
  Send a multi-turn conversation to a medical LLM.

  ## Examples

      messages = [
        %{role: "user", content: "Patient presents with chest pain"},
        %{role: "assistant", content: "I'll help analyze this. What are the associated symptoms?"},
        %{role: "user", content: "Radiating to left arm, diaphoresis, nausea"}
      ]

      {:ok, response} = MedlumLlm.chat_messages(messages)

  """
  @spec chat_messages([map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  defdelegate chat_messages(messages, opts \\ []), to: Chat

  @doc """
  Stream a chat response, yielding chunks as they arrive.

  ## Examples

      MedlumLlm.chat_stream("Explain diabetes management", fn chunk ->
        IO.write(chunk)
      end)

  """
  @spec chat_stream(String.t(), (String.t() -> any()), keyword()) :: :ok | {:error, term()}
  defdelegate chat_stream(message, callback, opts \\ []), to: Chat

  # =============================================================================
  # Embeddings API
  # =============================================================================

  @doc """
  Generate embeddings for clinical text.

  ## Options

    * `:model` - Embedding model to use (default: configured embed_model)

  ## Examples

      {:ok, embedding} = MedlumLlm.embed("Patient presents with acute chest pain")
      # => {:ok, [0.037, 0.013, -0.151, ...]}

  """
  @spec embed(String.t(), keyword()) :: {:ok, [float()]} | {:error, term()}
  defdelegate embed(text, opts \\ []), to: Embedder

  @doc """
  Generate embeddings for multiple texts in batch.

  ## Examples

      texts = ["myocardial infarction", "diabetes mellitus", "hypertension"]
      {:ok, embeddings} = MedlumLlm.embed_batch(texts)

  """
  @spec embed_batch([String.t()], keyword()) :: {:ok, [[float()]]} | {:error, term()}
  defdelegate embed_batch(texts, opts \\ []), to: Embedder

  @doc """
  Calculate cosine similarity between two clinical texts.

  Returns a value between -1 and 1, where 1 means identical semantic meaning.

  ## Examples

      {:ok, sim} = MedlumLlm.similarity("heart attack", "myocardial infarction")
      # => {:ok, 0.89}

      {:ok, sim} = MedlumLlm.similarity("diabetes", "broken arm")
      # => {:ok, 0.23}

  """
  @spec similarity(String.t(), String.t(), keyword()) :: {:ok, float()} | {:error, term()}
  defdelegate similarity(text1, text2, opts \\ []), to: Embedder

  # =============================================================================
  # Service Management API
  # =============================================================================

  @doc """
  Check if Ollama is running and responsive.

  ## Examples

      :ok = MedlumLlm.health_check()
      {:error, :econnrefused} = MedlumLlm.health_check()

  """
  @spec health_check(keyword()) :: :ok | {:error, term()}
  def health_check(opts \\ []) do
    client = get_client(opts)

    case Ollixir.list(client) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List all available models on the Ollama server.

  ## Examples

      {:ok, models} = MedlumLlm.list_models()
      # => {:ok, [%{name: "biomistral:7b", ...}, ...]}

  """
  @spec list_models(keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_models(opts \\ []) do
    client = get_client(opts)

    case Ollixir.list(client) do
      {:ok, %{"models" => models}} -> {:ok, models}
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get information about a specific model.

  ## Examples

      {:ok, info} = MedlumLlm.model_info(:biomistral_7b)

  """
  @spec model_info(atom() | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def model_info(model, opts \\ []) do
    client = get_client(opts)
    model_name = Models.resolve(model)

    case Ollixir.show(client, name: model_name) do
      {:ok, info} -> {:ok, info}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Pull a model from HuggingFace or Ollama registry.

  ## Examples

      # Pull by atom
      :ok = MedlumLlm.pull_model(:biomistral_7b)

      # Pull by full name
      :ok = MedlumLlm.pull_model("hf.co/BioMistral/BioMistral-7B-GGUF")

  """
  @spec pull_model(atom() | String.t(), keyword()) :: :ok | {:error, term()}
  def pull_model(model, opts \\ []) do
    client = get_client(opts)
    model_name = Models.resolve(model)

    case Ollixir.pull(client, name: model_name) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get all supported medical models with their metadata.

  ## Examples

      models = MedlumLlm.supported_models()
      # => %{biomistral_7b: %{name: "...", vram: "4GB", ...}, ...}

  """
  @spec supported_models() :: map()
  defdelegate supported_models(), to: Models, as: :all

  # =============================================================================
  # Datasets API
  # =============================================================================

  @doc """
  Load a medical evaluation dataset.

  See `MedlumLlm.Datasets.load/2` for full documentation.

  ## Examples

      {:ok, dataset} = MedlumLlm.load_dataset(:medqa)
      {:ok, dataset} = MedlumLlm.load_dataset(:medqa, sample: 100)

  """
  @spec load_dataset(atom(), keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  defdelegate load_dataset(name, opts \\ []), to: MedlumLlm.Datasets, as: :load

  @doc """
  List available medical datasets.

  ## Examples

      MedlumLlm.available_datasets()
      #=> [:medqa, :pubmedqa, :medmcqa, :reasonmed, :mmlu_medical, ...]

  """
  @spec available_datasets() :: [atom()]
  defdelegate available_datasets(), to: MedlumLlm.Datasets, as: :available

  # =============================================================================
  # Metrics API
  # =============================================================================

  @doc """
  Calculate accuracy for medical benchmark evaluation.

  See `MedlumLlm.Eval.MedicalMetrics.accuracy/2` for details.
  """
  @spec accuracy([term()], [map()]) :: float()
  defdelegate accuracy(predictions, samples),
    to: MedlumLlm.Eval.MedicalMetrics

  @doc """
  Calculate Wilson confidence interval for accuracy.

  See `MedlumLlm.Eval.MedicalMetrics.wilson_ci/3` for details.
  """
  @spec wilson_ci(integer(), integer(), float()) :: {float(), float()}
  def wilson_ci(successes, n, alpha \\ 0.05) do
    MedlumLlm.Eval.MedicalMetrics.wilson_ci(successes, n, alpha)
  end

  @doc """
  Calculate medication accuracy against RxNorm.

  See `MedlumLlm.Eval.MedicalMetrics.medication_accuracy/2` for details.
  """
  @spec medication_accuracy([map()], [map()]) :: float()
  defdelegate medication_accuracy(predictions, samples),
    to: MedlumLlm.Eval.MedicalMetrics

  @doc """
  Calculate diagnosis accuracy against ICD-10.

  See `MedlumLlm.Eval.MedicalMetrics.diagnosis_accuracy/2` for details.
  """
  @spec diagnosis_accuracy([map()], [map()]) :: float()
  defdelegate diagnosis_accuracy(predictions, samples),
    to: MedlumLlm.Eval.MedicalMetrics

  @doc """
  Calculate clinical safety composite score.

  See `MedlumLlm.Eval.MedicalMetrics.clinical_safety_score/3` for details.
  """
  @spec clinical_safety_score([map()], [map()], [map()]) :: float()
  defdelegate clinical_safety_score(predictions, samples, cvl_results),
    to: MedlumLlm.Eval.MedicalMetrics

  # =============================================================================
  # Math Utilities (exposed for advanced use)
  # =============================================================================

  @doc """
  Calculate cosine similarity between two vectors.

  ## Examples

      MedlumLlm.cosine_similarity([1, 0, 0], [1, 0, 0])
      # => 1.0

      MedlumLlm.cosine_similarity([1, 0, 0], [0, 1, 0])
      # => 0.0

  """
  @spec cosine_similarity([number()], [number()]) :: float()
  def cosine_similarity(vec_a, vec_b) when length(vec_a) == length(vec_b) do
    dot_product = Enum.zip(vec_a, vec_b) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()
    magnitude_a = :math.sqrt(Enum.map(vec_a, &(&1 * &1)) |> Enum.sum())
    magnitude_b = :math.sqrt(Enum.map(vec_b, &(&1 * &1)) |> Enum.sum())

    if magnitude_a == 0 or magnitude_b == 0 do
      0.0
    else
      dot_product / (magnitude_a * magnitude_b)
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp get_client(opts) do
    host = Keyword.get(opts, :host, get_config(:ollama_host, "http://localhost:11434"))
    Ollixir.init(host)
  end

  @doc false
  def get_config(key, default) do
    Application.get_env(:medlum_llm, key, default)
  end
end
