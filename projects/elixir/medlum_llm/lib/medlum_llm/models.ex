defmodule MedlumLlm.Models do
  @moduledoc """
  Model registry for medical LLMs available via Ollama.

  This module defines all supported medical language models with their
  metadata, VRAM requirements, and HuggingFace/Ollama pull commands.

  ## Model Categories

  ### Text Generation Models
  - BioMistral-7B: Medical domain fine-tuned Mistral
  - OpenBioLLM-8B: Open medical LLM based on Llama 3
  - OpenBioLLM-70B: Large medical LLM (requires >48GB VRAM)
  - Meditron-7B: Medical literature trained LLM
  - Meditron-70B: Large Meditron variant (requires >48GB VRAM)

  ### Embedding Models
  - nomic-embed-text: General purpose, good clinical performance
  - mxbai-embed-large: Higher quality embeddings

  ## VRAM Requirements

  For a 16GB GPU (like RTX 5060 Ti):
  - Safe: BioMistral-7B, OpenBioLLM-8B, Meditron-7B, all embedding models
  - Too large: OpenBioLLM-70B, Meditron-70B
  """

  @models %{
    # ==========================================================================
    # Text Generation Models (Ollama-compatible GGUF)
    # ==========================================================================
    biomistral_7b: %{
      name: "hf.co/BioMistral/BioMistral-7B-GGUF",
      display_name: "BioMistral-7B",
      type: :chat,
      parameters: "7B",
      vram_required: "~4GB (Q4_K_M)",
      fits_16gb: true,
      description: "Medical domain fine-tuned Mistral 7B. Trained on PubMed articles.",
      use_cases: ["Medical Q&A", "Clinical text generation", "Medical summarization"],
      pull_command: "ollama pull hf.co/BioMistral/BioMistral-7B-GGUF",
      huggingface_url: "https://huggingface.co/BioMistral/BioMistral-7B-GGUF"
    },
    openbio_8b: %{
      name: "hf.co/MoMonir/Llama3-OpenBioLLM-8B-GGUF",
      display_name: "OpenBioLLM-8B",
      type: :chat,
      parameters: "8B",
      vram_required: "~5GB (Q4_K_M)",
      fits_16gb: true,
      description: "Open medical LLM based on Llama 3. Strong medical reasoning.",
      use_cases: ["Medical reasoning", "Differential diagnosis", "Clinical decision support"],
      pull_command: "ollama pull hf.co/MoMonir/Llama3-OpenBioLLM-8B-GGUF",
      huggingface_url: "https://huggingface.co/MoMonir/Llama3-OpenBioLLM-8B-GGUF"
    },
    openbio_70b: %{
      name: "hf.co/aaditya/Llama3-OpenBioLLM-70B-GGUF",
      display_name: "OpenBioLLM-70B",
      type: :chat,
      parameters: "70B",
      vram_required: "~40GB (Q4_K_M)",
      fits_16gb: false,
      description: "Large open medical LLM. Highest quality but requires significant VRAM.",
      use_cases: ["Complex medical reasoning", "Research assistance", "Expert-level Q&A"],
      pull_command: "ollama pull hf.co/aaditya/Llama3-OpenBioLLM-70B-GGUF",
      huggingface_url: "https://huggingface.co/aaditya/Llama3-OpenBioLLM-70B-GGUF",
      warning: "Requires >40GB VRAM - will not fit on 16GB GPU"
    },
    meditron_7b: %{
      name: "hf.co/TheBloke/meditron-7B-GGUF",
      display_name: "Meditron-7B",
      type: :chat,
      parameters: "7B",
      vram_required: "~4GB (Q4_K_M)",
      fits_16gb: true,
      description: "Medical LLM trained on clinical guidelines and medical literature.",
      use_cases: ["Evidence-based medicine", "Clinical guidelines", "Medical literature"],
      pull_command: "ollama pull hf.co/TheBloke/meditron-7B-GGUF",
      huggingface_url: "https://huggingface.co/TheBloke/meditron-7B-GGUF"
    },
    meditron_70b: %{
      name: "hf.co/TheBloke/meditron-70B-GGUF",
      display_name: "Meditron-70B",
      type: :chat,
      parameters: "70B",
      vram_required: "~40GB (Q4_K_M)",
      fits_16gb: false,
      description: "Large Meditron model for highest quality medical text generation.",
      use_cases: ["Complex medical literature", "Research", "Expert consultation"],
      pull_command: "ollama pull hf.co/TheBloke/meditron-70B-GGUF",
      huggingface_url: "https://huggingface.co/TheBloke/meditron-70B-GGUF",
      warning: "Requires >40GB VRAM - will not fit on 16GB GPU"
    },

    # ==========================================================================
    # Embedding Models
    # ==========================================================================
    nomic_embed: %{
      name: "nomic-embed-text",
      display_name: "Nomic Embed Text",
      type: :embed,
      parameters: "137M",
      vram_required: "<1GB",
      fits_16gb: true,
      dimensions: 768,
      description: "General purpose embedding model with good clinical text performance.",
      use_cases: ["Semantic search", "Clinical note similarity", "Document clustering"],
      pull_command: "ollama pull nomic-embed-text"
    },
    mxbai_embed: %{
      name: "mxbai-embed-large",
      display_name: "MixedBread Embed Large",
      type: :embed,
      parameters: "335M",
      vram_required: "<2GB",
      fits_16gb: true,
      dimensions: 1024,
      description: "Higher quality embeddings for advanced similarity tasks.",
      use_cases: ["High-precision similarity", "Medical concept matching", "Retrieval"],
      pull_command: "ollama pull mxbai-embed-large"
    }
  }

  @doc """
  Get all supported models with their metadata.
  """
  @spec all() :: map()
  def all, do: @models

  @doc """
  Get models that fit on a specific VRAM budget.

  ## Examples

      MedlumLlm.Models.fits_vram(16)
      # => [:biomistral_7b, :openbio_8b, :meditron_7b, :nomic_embed, :mxbai_embed]

  """
  @spec fits_vram(integer()) :: [atom()]
  def fits_vram(gb) when gb >= 16 do
    @models
    |> Enum.filter(fn {_key, model} -> model.fits_16gb end)
    |> Enum.map(fn {key, _model} -> key end)
  end

  def fits_vram(_gb), do: [:nomic_embed, :mxbai_embed]

  @doc """
  Get only chat/generation models.
  """
  @spec chat_models() :: map()
  def chat_models do
    @models |> Enum.filter(fn {_k, v} -> v.type == :chat end) |> Map.new()
  end

  @doc """
  Get only embedding models.
  """
  @spec embed_models() :: map()
  def embed_models do
    @models |> Enum.filter(fn {_k, v} -> v.type == :embed end) |> Map.new()
  end

  @doc """
  Resolve a model atom or string to its Ollama pull name.

  ## Examples

      MedlumLlm.Models.resolve(:biomistral_7b)
      # => "hf.co/BioMistral/BioMistral-7B-GGUF"

      MedlumLlm.Models.resolve("custom-model:latest")
      # => "custom-model:latest"

  """
  @spec resolve(atom() | String.t()) :: String.t()
  def resolve(model) when is_atom(model) do
    case Map.get(@models, model) do
      nil -> Atom.to_string(model)
      model_info -> model_info.name
    end
  end

  def resolve(model) when is_binary(model), do: model

  @doc """
  Get metadata for a specific model.

  ## Examples

      {:ok, info} = MedlumLlm.Models.get(:biomistral_7b)

  """
  @spec get(atom()) :: {:ok, map()} | {:error, :not_found}
  def get(model) when is_atom(model) do
    case Map.get(@models, model) do
      nil -> {:error, :not_found}
      model_info -> {:ok, model_info}
    end
  end

  @doc """
  Get the default chat model.
  """
  @spec default_chat_model() :: String.t()
  def default_chat_model do
    Application.get_env(:medlum_llm, :chat_model, @models.biomistral_7b.name)
  end

  @doc """
  Get the default embedding model.
  """
  @spec default_embed_model() :: String.t()
  def default_embed_model do
    Application.get_env(:medlum_llm, :embed_model, @models.nomic_embed.name)
  end

  @doc """
  Print a summary of all models for CLI use.
  """
  @spec print_summary() :: :ok
  def print_summary do
    IO.puts("\n=== MedlumLlm Supported Models ===\n")

    IO.puts("TEXT GENERATION (Chat) Models:")
    IO.puts(String.duplicate("-", 70))

    chat_models()
    |> Enum.sort_by(fn {_k, v} -> v.parameters end)
    |> Enum.each(fn {key, model} ->
      status = if model.fits_16gb, do: "[OK 16GB]", else: "[>40GB]"
      IO.puts("  #{status} :#{key}")
      IO.puts("         #{model.display_name} (#{model.parameters})")
      IO.puts("         #{model.description}")
      IO.puts("")
    end)

    IO.puts("\nEMBEDDING Models:")
    IO.puts(String.duplicate("-", 70))

    embed_models()
    |> Enum.each(fn {key, model} ->
      IO.puts("  [OK 16GB] :#{key}")
      IO.puts("            #{model.display_name} (#{model.dimensions} dims)")
      IO.puts("            #{model.description}")
      IO.puts("")
    end)

    :ok
  end
end
