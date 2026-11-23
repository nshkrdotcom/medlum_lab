defmodule MedlumLlm.Chat do
  @moduledoc """
  Chat/text generation functionality for medical LLMs.

  This module provides the interface for interacting with medical language models
  like BioMistral, OpenBioLLM, and Meditron through Ollama.

  ## Supported Models

  - `:biomistral_7b` - BioMistral-7B (default)
  - `:openbio_8b` - OpenBioLLM-8B
  - `:meditron_7b` - Meditron-7B

  ## Usage

      # Simple query
      {:ok, response} = MedlumLlm.Chat.chat("What is hypertension?")

      # With options
      {:ok, response} = MedlumLlm.Chat.chat(
        "Explain diabetes management",
        model: :openbio_8b,
        temperature: 0.7
      )

  """

  alias MedlumLlm.Models

  require Logger

  @default_system_prompt """
  You are a knowledgeable medical assistant. Provide accurate, evidence-based
  medical information. Always recommend consulting a healthcare professional
  for personal medical advice. Be clear about the limitations of AI-generated
  medical information.
  """

  @doc """
  Send a message to a medical LLM and get a response.

  ## Options

    * `:model` - Model atom or string (default: :biomistral_7b)
    * `:system` - System prompt (default: medical assistant prompt)
    * `:temperature` - Sampling temperature 0.0-1.0 (default: 0.7)
    * `:max_tokens` - Maximum tokens in response
    * `:host` - Ollama host URL

  """
  @spec chat(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat(message, opts \\ []) do
    messages = [%{role: "user", content: message}]
    chat_messages(messages, opts)
  end

  @doc """
  Send a multi-turn conversation to a medical LLM.

  Messages should be a list of maps with :role and :content keys.
  Roles can be "user", "assistant", or "system".

  ## Examples

      messages = [
        %{role: "user", content: "What are symptoms of MI?"},
        %{role: "assistant", content: "Common symptoms include..."},
        %{role: "user", content: "What about silent MI?"}
      ]
      {:ok, response} = MedlumLlm.Chat.chat_messages(messages)

  """
  @spec chat_messages([map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat_messages(messages, opts \\ []) do
    # Get timeout from opts, default to 120 seconds (passed to client init)
    timeout = Keyword.get(opts, :timeout, 120_000)
    client = get_client(opts, timeout)
    model = get_model(opts)
    system = Keyword.get(opts, :system, @default_system_prompt)
    temperature = Keyword.get(opts, :temperature, 0.7)

    # Prepend system message if not already present
    messages_with_system =
      if has_system_message?(messages) do
        messages
      else
        [%{role: "system", content: system} | messages]
      end

    Logger.debug("Sending chat request to #{model} with #{length(messages_with_system)} messages")

    # Build the options map for Ollama model parameters
    model_options =
      %{}
      |> maybe_put(:temperature, temperature)
      |> maybe_put(:num_predict, Keyword.get(opts, :max_tokens))

    chat_opts =
      [
        model: model,
        messages: normalize_messages(messages_with_system),
        stream: false
      ]
      |> maybe_add_options(model_options)

    case Ollixir.chat(client, chat_opts) do
      {:ok, %{"message" => %{"content" => content}}} ->
        {:ok, content}

      {:ok, response} ->
        Logger.warning("Unexpected chat response format: #{inspect(response)}")
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stream a chat response, yielding chunks to the callback function.

  The callback receives each text chunk as it arrives.

  ## Examples

      MedlumLlm.Chat.chat_stream("Explain hypertension", fn chunk ->
        IO.write(chunk)
      end)

  """
  @spec chat_stream(String.t(), (String.t() -> any()), keyword()) :: :ok | {:error, term()}
  def chat_stream(message, callback, opts \\ []) when is_function(callback, 1) do
    timeout = Keyword.get(opts, :timeout, 120_000)
    client = get_client(opts, timeout)
    model = get_model(opts)
    system = Keyword.get(opts, :system, @default_system_prompt)

    messages = [
      %{role: "system", content: system},
      %{role: "user", content: message}
    ]

    Logger.debug("Starting streaming chat with #{model}")

    chat_opts = [
      model: model,
      messages: normalize_messages(messages),
      stream: true
    ]

    case Ollixir.chat(client, chat_opts) do
      {:ok, stream} when is_function(stream) ->
        # Handle streaming response
        stream
        |> Stream.each(fn
          %{"message" => %{"content" => chunk}} -> callback.(chunk)
          _ -> :ok
        end)
        |> Stream.run()

        :ok

      {:ok, %{"message" => %{"content" => content}}} ->
        # Fallback if streaming not available
        callback.(content)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate text completion (non-chat format).

  This is useful for completing clinical text or generating continuations.

  ## Examples

      {:ok, completion} = MedlumLlm.Chat.complete(
        "The patient presents with chest pain and",
        model: :biomistral_7b
      )

  """
  @spec complete(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def complete(prompt, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 120_000)
    client = get_client(opts, timeout)
    model = get_model(opts)

    generate_opts = [
      model: model,
      prompt: prompt,
      stream: false
    ]

    case Ollixir.generate(client, generate_opts) do
      {:ok, %{"response" => response}} ->
        {:ok, response}

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp get_client(opts, receive_timeout) do
    host = Keyword.get(opts, :host, MedlumLlm.get_config(:ollama_host, "http://localhost:11434"))
    Ollixir.init(base_url: host, receive_timeout: receive_timeout)
  end

  defp get_model(opts) do
    model = Keyword.get(opts, :model, :biomistral_7b)
    Models.resolve(model)
  end

  defp has_system_message?(messages) do
    Enum.any?(messages, fn msg ->
      msg[:role] == "system" or msg["role"] == "system"
    end)
  end

  defp normalize_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        role: to_string(msg[:role] || msg["role"]),
        content: msg[:content] || msg["content"]
      }
    end)
  end

  # Add value to map only if not nil
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Add options to keyword list only if map is non-empty
  defp maybe_add_options(opts_list, options) when map_size(options) == 0, do: opts_list
  defp maybe_add_options(opts_list, options), do: Keyword.put(opts_list, :options, options)
end
