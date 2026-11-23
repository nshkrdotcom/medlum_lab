defmodule MedlumLlm.Profile do
  @moduledoc """
  Configuration profiles for different deployment contexts.

  Profiles configure model selection and behavior based on:
  - Development vs Production
  - Interactive vs Batch processing
  - Hardware constraints

  ## Available Profiles

  - `:dev_fast` - Fast iteration during development (8GB VRAM)
  - `:dev_full` - Full stack development (16GB VRAM)
  - `:test` - Testing with mock providers
  - `:prod_interactive` - Production interactive use
  - `:prod_batch` - Production batch processing
  - `:prod_critical` - Production critical decisions

  ## Usage

      # Set profile
      Profile.set(:prod_interactive)

      # Get current profile settings
      profile = Profile.current()

      # Get model for current profile
      model = Profile.chat_model()

  """

  @type profile_id :: atom()
  @type profile :: %{
          name: String.t(),
          chat_model: atom(),
          embed_model: atom(),
          ner_provider: atom(),
          pii_provider: atom(),
          max_vram_gb: integer(),
          timeout_multiplier: float(),
          require_verification: boolean()
        }

  @profiles %{
    dev_fast: %{
      name: "Development - Fast",
      chat_model: :biomistral_7b,
      embed_model: :nomic_embed,
      ner_provider: :mock,
      pii_provider: :mock,
      max_vram_gb: 8,
      timeout_multiplier: 0.5,
      require_verification: false
    },
    dev_full: %{
      name: "Development - Full Stack",
      chat_model: :openbio_8b,
      embed_model: :nomic_embed,
      ner_provider: :huggingface,
      pii_provider: :huggingface,
      max_vram_gb: 16,
      timeout_multiplier: 1.0,
      require_verification: false
    },
    test: %{
      name: "Testing",
      chat_model: :mock,
      embed_model: :mock,
      ner_provider: :mock,
      pii_provider: :mock,
      max_vram_gb: 0,
      timeout_multiplier: 0.1,
      require_verification: false
    },
    prod_interactive: %{
      name: "Production - Interactive",
      chat_model: :ii_medical_8b,
      embed_model: :nomic_embed,
      ner_provider: :huggingface,
      pii_provider: :huggingface,
      max_vram_gb: 16,
      timeout_multiplier: 1.0,
      require_verification: false
    },
    prod_batch: %{
      name: "Production - Batch",
      chat_model: :openbio_70b,
      embed_model: :mxbai_embed,
      ner_provider: :huggingface,
      pii_provider: :huggingface,
      max_vram_gb: 16,
      timeout_multiplier: 5.0,
      require_verification: false
    },
    prod_critical: %{
      name: "Production - Critical",
      chat_model: :med42_70b,
      embed_model: :mxbai_embed,
      ner_provider: :huggingface,
      pii_provider: :huggingface,
      max_vram_gb: 16,
      timeout_multiplier: 10.0,
      require_verification: true
    }
  }

  @production_profiles [:prod_interactive, :prod_batch, :prod_critical]

  # ==========================================================================
  # Public API
  # ==========================================================================

  @doc """
  Returns all available profiles.
  """
  @spec all() :: %{profile_id() => profile()}
  def all, do: @profiles

  @doc """
  Gets a profile by its ID.
  """
  @spec get(profile_id()) :: {:ok, profile()} | {:error, :not_found}
  def get(profile_id) do
    case Map.fetch(@profiles, profile_id) do
      {:ok, profile} -> {:ok, profile}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Returns the current active profile configuration.
  """
  @spec current() :: profile()
  def current do
    profile_id = Application.get_env(:medlum_llm, :profile, :dev_fast)

    case get(profile_id) do
      {:ok, profile} -> profile
      {:error, :not_found} -> Map.fetch!(@profiles, :dev_fast)
    end
  end

  @doc """
  Returns the current profile ID.
  """
  @spec current_id() :: profile_id()
  def current_id do
    Application.get_env(:medlum_llm, :profile, :dev_fast)
  end

  @doc """
  Sets the current profile.
  """
  @spec set(profile_id()) :: :ok | {:error, :not_found}
  def set(profile_id) do
    case get(profile_id) do
      {:ok, _profile} ->
        Application.put_env(:medlum_llm, :profile, profile_id)
        :ok

      error ->
        error
    end
  end

  @doc """
  Returns the chat model for the current profile.
  """
  @spec chat_model() :: atom()
  def chat_model do
    current().chat_model
  end

  @doc """
  Returns the embedding model for the current profile.
  """
  @spec embed_model() :: atom()
  def embed_model do
    current().embed_model
  end

  @doc """
  Returns the NER provider for the current profile.
  """
  @spec ner_provider() :: atom()
  def ner_provider do
    current().ner_provider
  end

  @doc """
  Returns the PII provider for the current profile.
  """
  @spec pii_provider() :: atom()
  def pii_provider do
    current().pii_provider
  end

  @doc """
  Applies the timeout multiplier from the current profile.
  """
  @spec timeout(integer()) :: integer()
  def timeout(base_ms) do
    round(base_ms * current().timeout_multiplier)
  end

  @doc """
  Returns a list of available profile names.
  """
  @spec available() :: [profile_id()]
  def available do
    Map.keys(@profiles)
  end

  @doc """
  Returns true if the current profile is a production profile.
  """
  @spec is_production?() :: boolean()
  def is_production? do
    current_id() in @production_profiles
  end

  @doc """
  Returns true if verification is required for the current profile.
  """
  @spec require_verification?() :: boolean()
  def require_verification? do
    current().require_verification
  end

  @doc """
  Returns the maximum VRAM budget for the current profile.
  """
  @spec max_vram() :: integer()
  def max_vram do
    current().max_vram_gb
  end

  @doc """
  Temporarily use a different profile for a function.
  """
  @spec with_profile(profile_id(), (-> term())) :: term()
  def with_profile(profile_id, fun) do
    original = current_id()

    try do
      set(profile_id)
      fun.()
    after
      set(original)
    end
  end
end
