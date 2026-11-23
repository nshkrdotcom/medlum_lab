defmodule MedlumLlm.Provider do
  @moduledoc """
  Provider behaviour and registry for model inference backends.

  Providers abstract the execution layer, allowing the same model interface
  to work with different backends:

  - `:ollama` - Local LLM inference via Ollama
  - `:huggingface` - HuggingFace Transformers via Python/Snakebridge
  - `:mock` - Mock provider for testing

  ## Implementing a Provider

      defmodule MyProvider do
        @behaviour MedlumLlm.Provider

        @impl true
        def generate(model_id, prompt, opts) do
          # Implementation
        end

        # ... other callbacks
      end

  """

  @type model_id :: atom()
  @type input :: String.t() | [String.t()]
  @type opts :: keyword()
  @type result :: {:ok, term()} | {:error, term()}

  @callback generate(model_id(), String.t(), opts()) :: result()
  @callback embed(model_id(), [String.t()], opts()) :: result()
  @callback extract_entities(model_id(), String.t(), opts()) :: result()
  @callback health_check() :: :ok | {:error, term()}

  @optional_callbacks [generate: 3, embed: 3, extract_entities: 3]

  # Provider registry
  @providers %{
    ollama: MedlumLlm.Provider.Ollama,
    huggingface: MedlumLlm.Provider.HuggingFace,
    mock: MedlumLlm.Provider.Mock
  }

  @doc """
  Gets a provider module by its ID.
  """
  @spec get(atom()) :: {:ok, module()} | {:error, :unknown_provider}
  def get(provider_id) do
    case Map.fetch(@providers, provider_id) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_provider}
    end
  end

  @doc """
  Returns a list of all available provider IDs.
  """
  @spec available() :: [atom()]
  def available do
    Map.keys(@providers)
  end

  @doc """
  Dispatches an operation to the appropriate provider.
  """
  @spec dispatch(atom(), atom(), [term()]) :: term()
  def dispatch(provider_id, operation, args) do
    case get(provider_id) do
      {:ok, provider} -> apply(provider, operation, args)
      error -> error
    end
  end
end

defmodule MedlumLlm.Provider.Ollama do
  @moduledoc """
  Ollama provider for local LLM inference.

  Uses the Ollixir library to communicate with the Ollama server.
  """

  @behaviour MedlumLlm.Provider

  @impl true
  def generate(model_id, prompt, opts) do
    MedlumLlm.Chat.chat(prompt, Keyword.put(opts, :model, model_id))
  end

  @impl true
  def embed(model_id, texts, opts) do
    MedlumLlm.Embedder.embed_batch(texts, Keyword.put(opts, :model, model_id))
  end

  @impl true
  def extract_entities(_model_id, _text, _opts) do
    {:error, :not_supported}
  end

  @impl true
  def health_check do
    client = Ollixir.init(MedlumLlm.get_config(:ollama_host, "http://localhost:11434"))

    case Ollixir.list_models(client) do
      {:ok, _} -> :ok
      error -> {:error, error}
    end
  end
end

defmodule MedlumLlm.Provider.HuggingFace do
  @moduledoc """
  HuggingFace provider for Transformers models.

  Uses Python via Snakebridge (not yet implemented).
  """

  @behaviour MedlumLlm.Provider

  @impl true
  def generate(_model_id, _prompt, _opts) do
    {:error, :not_implemented}
  end

  @impl true
  def embed(_model_id, _texts, _opts) do
    {:error, :not_implemented}
  end

  @impl true
  def extract_entities(_model_id, _text, _opts) do
    {:error, :not_implemented}
  end

  @impl true
  def health_check do
    # Would check Python environment and model availability
    {:error, :not_implemented}
  end
end

defmodule MedlumLlm.Provider.Mock do
  @moduledoc """
  Mock provider for testing.

  Returns deterministic responses for testing purposes.
  """

  @behaviour MedlumLlm.Provider

  @impl true
  def generate(_model_id, prompt, _opts) do
    response = "This is a mock response to: #{truncate(prompt, 50)}"
    {:ok, response}
  end

  @impl true
  def embed(model_id, texts, _opts) do
    dimensions = get_dimensions(model_id)

    embeddings =
      Enum.map(texts, fn text ->
        # Generate deterministic pseudo-random embedding based on text hash
        seed = :erlang.phash2(text)
        :rand.seed(:exsplus, {seed, seed, seed})
        Enum.map(1..dimensions, fn _ -> :rand.uniform() - 0.5 end)
      end)

    {:ok, embeddings}
  end

  @impl true
  def extract_entities(_model_id, text, _opts) do
    # Return mock entities based on simple pattern matching
    entities = extract_mock_entities(text)
    {:ok, entities}
  end

  @impl true
  def health_check do
    :ok
  end

  # Private helpers

  defp truncate(string, max_length) when byte_size(string) <= max_length, do: string
  defp truncate(string, max_length), do: String.slice(string, 0, max_length) <> "..."

  defp get_dimensions(model_id) do
    case model_id do
      :mxbai_embed -> 1024
      _ -> 768
    end
  end

  defp extract_mock_entities(text) do
    # Simple mock extraction - in reality would use the model
    entities = []

    entities =
      if String.contains?(String.downcase(text), "diabetes") do
        [%{type: "DISEASE", text: "diabetes", start: 0, end: 8} | entities]
      else
        entities
      end

    entities =
      if String.contains?(String.downcase(text), "hypertension") do
        [%{type: "DISEASE", text: "hypertension", start: 0, end: 12} | entities]
      else
        entities
      end

    entities =
      if String.contains?(String.downcase(text), "metformin") do
        [%{type: "MEDICATION", text: "metformin", start: 0, end: 9} | entities]
      else
        entities
      end

    entities =
      if String.contains?(String.downcase(text), "patient") do
        [%{type: "PATIENT", text: "[PATIENT]", start: 0, end: 7} | entities]
      else
        entities
      end

    # Return at least one mock entity if none found
    if entities == [] do
      [%{type: "UNKNOWN", text: "mock_entity", start: 0, end: 11}]
    else
      entities
    end
  end
end
