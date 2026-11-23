defmodule MedlumLlm.ProfileTest do
  use ExUnit.Case

  alias MedlumLlm.Profile

  # Clean up after each test
  setup do
    # Store original profile
    original = Application.get_env(:medlum_llm, :profile, :dev_fast)

    on_exit(fn ->
      Application.put_env(:medlum_llm, :profile, original)
    end)

    :ok
  end

  describe "all/0" do
    test "returns all available profiles" do
      profiles = Profile.all()

      assert is_map(profiles)
      assert Map.has_key?(profiles, :dev_fast)
      assert Map.has_key?(profiles, :dev_full)
      assert Map.has_key?(profiles, :test)
      assert Map.has_key?(profiles, :prod_interactive)
      assert Map.has_key?(profiles, :prod_batch)
      assert Map.has_key?(profiles, :prod_critical)
    end
  end

  describe "get/1" do
    test "returns dev_fast profile" do
      assert {:ok, profile} = Profile.get(:dev_fast)

      assert profile.name == "Development - Fast"
      assert profile.chat_model == :biomistral_7b
      assert profile.embed_model == :nomic_embed
      assert profile.max_vram_gb == 8
    end

    test "returns dev_full profile" do
      assert {:ok, profile} = Profile.get(:dev_full)

      assert profile.name == "Development - Full Stack"
      assert profile.chat_model == :openbio_8b
    end

    test "returns test profile" do
      assert {:ok, profile} = Profile.get(:test)

      assert profile.name == "Testing"
      assert profile.chat_model == :mock
      assert profile.embed_model == :mock
      assert profile.ner_provider == :mock
      assert profile.pii_provider == :mock
    end

    test "returns prod_interactive profile" do
      assert {:ok, profile} = Profile.get(:prod_interactive)

      assert profile.name == "Production - Interactive"
      assert profile.chat_model == :ii_medical_8b
    end

    test "returns prod_batch profile" do
      assert {:ok, profile} = Profile.get(:prod_batch)

      assert profile.name == "Production - Batch"
      assert profile.chat_model == :openbio_70b
      assert profile.timeout_multiplier >= 5.0
    end

    test "returns prod_critical profile" do
      assert {:ok, profile} = Profile.get(:prod_critical)

      assert profile.name == "Production - Critical"
      assert profile.chat_model == :med42_70b
      assert profile.require_verification == true
    end

    test "returns error for unknown profile" do
      assert {:error, :not_found} = Profile.get(:unknown_profile)
    end
  end

  describe "current/0" do
    test "returns default profile when not set" do
      Application.delete_env(:medlum_llm, :profile)

      profile = Profile.current()

      # Default should be dev_fast
      assert profile.chat_model == :biomistral_7b
    end

    test "returns configured profile" do
      Application.put_env(:medlum_llm, :profile, :prod_interactive)

      profile = Profile.current()

      assert profile.chat_model == :ii_medical_8b
    end
  end

  describe "set/1" do
    test "sets the current profile" do
      assert :ok = Profile.set(:prod_batch)

      profile = Profile.current()
      assert profile.chat_model == :openbio_70b
    end

    test "returns error for invalid profile" do
      assert {:error, :not_found} = Profile.set(:invalid_profile)
    end
  end

  describe "chat_model/0" do
    test "returns chat model for current profile" do
      Profile.set(:dev_fast)

      assert :biomistral_7b = Profile.chat_model()
    end

    test "returns mock for test profile" do
      Profile.set(:test)

      assert :mock = Profile.chat_model()
    end
  end

  describe "embed_model/0" do
    test "returns embed model for current profile" do
      Profile.set(:dev_fast)

      assert :nomic_embed = Profile.embed_model()
    end

    test "returns mock for test profile" do
      Profile.set(:test)

      assert :mock = Profile.embed_model()
    end
  end

  describe "timeout/1" do
    test "applies timeout multiplier from profile" do
      Profile.set(:dev_fast)
      assert Profile.timeout(60_000) == 30_000

      Profile.set(:prod_batch)
      assert Profile.timeout(60_000) >= 300_000
    end
  end

  describe "ner_provider/0" do
    test "returns provider for current profile" do
      Profile.set(:dev_full)

      assert :huggingface = Profile.ner_provider()
    end

    test "returns mock for test profile" do
      Profile.set(:test)

      assert :mock = Profile.ner_provider()
    end
  end

  describe "pii_provider/0" do
    test "returns provider for current profile" do
      Profile.set(:prod_interactive)

      assert :huggingface = Profile.pii_provider()
    end

    test "returns mock for test profile" do
      Profile.set(:test)

      assert :mock = Profile.pii_provider()
    end
  end

  describe "available/0" do
    test "returns list of profile names" do
      profiles = Profile.available()

      assert is_list(profiles)
      assert :dev_fast in profiles
      assert :test in profiles
      assert :prod_critical in profiles
    end
  end

  describe "is_production?/0" do
    test "returns false for dev profiles" do
      Profile.set(:dev_fast)
      refute Profile.is_production?()

      Profile.set(:dev_full)
      refute Profile.is_production?()
    end

    test "returns false for test profile" do
      Profile.set(:test)
      refute Profile.is_production?()
    end

    test "returns true for production profiles" do
      Profile.set(:prod_interactive)
      assert Profile.is_production?()

      Profile.set(:prod_batch)
      assert Profile.is_production?()

      Profile.set(:prod_critical)
      assert Profile.is_production?()
    end
  end
end
