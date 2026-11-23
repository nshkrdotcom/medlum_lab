defmodule MedlumLlm.ModelsTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Models

  describe "all/0" do
    test "returns map of all models" do
      models = Models.all()

      assert is_map(models)
      assert map_size(models) >= 6
    end
  end

  describe "resolve/1" do
    test "resolves atom to model name" do
      assert Models.resolve(:biomistral_7b) == "hf.co/BioMistral/BioMistral-7B-GGUF"
      assert Models.resolve(:openbio_8b) == "hf.co/MoMonir/Llama3-OpenBioLLM-8B-GGUF"
      assert Models.resolve(:meditron_7b) == "hf.co/TheBloke/meditron-7B-GGUF"
      assert Models.resolve(:nomic_embed) == "nomic-embed-text"
    end

    test "passes through string model names" do
      assert Models.resolve("custom-model:latest") == "custom-model:latest"
      assert Models.resolve("hf.co/user/model-GGUF") == "hf.co/user/model-GGUF"
    end

    test "converts unknown atoms to strings" do
      assert Models.resolve(:unknown_model) == "unknown_model"
    end
  end

  describe "get/1" do
    test "returns model info for known models" do
      {:ok, info} = Models.get(:biomistral_7b)

      assert info.name == "hf.co/BioMistral/BioMistral-7B-GGUF"
      assert info.type == :chat
      assert info.parameters == "7B"
      assert info.fits_16gb == true
    end

    test "returns error for unknown models" do
      assert {:error, :not_found} = Models.get(:nonexistent_model)
    end
  end

  describe "fits_vram/1" do
    test "returns models fitting 16GB" do
      models = Models.fits_vram(16)

      assert :biomistral_7b in models
      assert :openbio_8b in models
      assert :meditron_7b in models
      assert :nomic_embed in models

      # 70B models should NOT be included
      refute :openbio_70b in models
      refute :meditron_70b in models
    end

    test "returns only embedding models for small VRAM" do
      models = Models.fits_vram(4)

      assert :nomic_embed in models
      assert :mxbai_embed in models
      refute :biomistral_7b in models
    end
  end

  describe "chat_models/0" do
    test "returns only chat models" do
      models = Models.chat_models()

      Enum.each(models, fn {_key, model} ->
        assert model.type == :chat
      end)

      assert Map.has_key?(models, :biomistral_7b)
      refute Map.has_key?(models, :nomic_embed)
    end
  end

  describe "embed_models/0" do
    test "returns only embedding models" do
      models = Models.embed_models()

      Enum.each(models, fn {_key, model} ->
        assert model.type == :embed
      end)

      assert Map.has_key?(models, :nomic_embed)
      refute Map.has_key?(models, :biomistral_7b)
    end
  end

  describe "default_chat_model/0" do
    test "returns a valid model name" do
      model = Models.default_chat_model()
      assert is_binary(model)
      assert String.length(model) > 0
    end
  end

  describe "default_embed_model/0" do
    test "returns a valid model name" do
      model = Models.default_embed_model()
      assert is_binary(model)
      assert String.length(model) > 0
    end
  end
end
