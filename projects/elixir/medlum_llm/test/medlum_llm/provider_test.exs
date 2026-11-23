defmodule MedlumLlm.ProviderTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Provider

  describe "behaviour" do
    test "Provider.Mock implements the behaviour" do
      # Ensure module is loaded
      Code.ensure_loaded!(MedlumLlm.Provider.Mock)

      assert function_exported?(MedlumLlm.Provider.Mock, :generate, 3)
      assert function_exported?(MedlumLlm.Provider.Mock, :embed, 3)
      assert function_exported?(MedlumLlm.Provider.Mock, :extract_entities, 3)
      assert function_exported?(MedlumLlm.Provider.Mock, :health_check, 0)
    end
  end

  describe "get/1" do
    test "returns Ollama provider" do
      assert {:ok, provider} = Provider.get(:ollama)
      assert provider == MedlumLlm.Provider.Ollama
    end

    test "returns HuggingFace provider" do
      assert {:ok, provider} = Provider.get(:huggingface)
      assert provider == MedlumLlm.Provider.HuggingFace
    end

    test "returns Mock provider" do
      assert {:ok, provider} = Provider.get(:mock)
      assert provider == MedlumLlm.Provider.Mock
    end

    test "returns error for unknown provider" do
      assert {:error, :unknown_provider} = Provider.get(:unknown)
    end
  end

  describe "available/0" do
    test "lists all registered providers" do
      providers = Provider.available()

      assert :ollama in providers
      assert :huggingface in providers
      assert :mock in providers
    end
  end
end

defmodule MedlumLlm.Provider.MockTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Provider.Mock

  describe "generate/3" do
    test "returns mock response" do
      assert {:ok, response} = Mock.generate(:biomistral_7b, "What is diabetes?", [])

      assert is_binary(response)
      assert String.contains?(response, "mock")
    end

    test "includes prompt in response" do
      assert {:ok, response} = Mock.generate(:openbio_8b, "Explain hypertension", [])

      assert String.contains?(response, "hypertension")
    end
  end

  describe "embed/3" do
    test "returns mock embedding for single text" do
      assert {:ok, embeddings} = Mock.embed(:nomic_embed, ["test text"], [])

      assert is_list(embeddings)
      assert length(embeddings) == 1

      [embedding] = embeddings
      assert is_list(embedding)
      assert length(embedding) == 768
      assert Enum.all?(embedding, &is_float/1)
    end

    test "returns mock embeddings for batch" do
      texts = ["text1", "text2", "text3"]
      assert {:ok, embeddings} = Mock.embed(:nomic_embed, texts, [])

      assert length(embeddings) == 3
    end

    test "returns different dimensions for mxbai model" do
      assert {:ok, embeddings} = Mock.embed(:mxbai_embed, ["test"], [])

      [embedding] = embeddings
      assert length(embedding) == 1024
    end
  end

  describe "extract_entities/3" do
    test "returns mock entities for disease text" do
      text = "The patient has diabetes and hypertension"
      assert {:ok, entities} = Mock.extract_entities(:openmed_disease_superclinical, text, [])

      assert is_list(entities)
      assert length(entities) >= 1

      Enum.each(entities, fn entity ->
        assert Map.has_key?(entity, :type)
        assert Map.has_key?(entity, :text)
        assert Map.has_key?(entity, :start)
        assert Map.has_key?(entity, :end)
      end)
    end

    test "returns mock entities for medication text" do
      text = "Prescribed metformin 500mg twice daily"
      assert {:ok, entities} = Mock.extract_entities(:openmed_pharma_superclinical, text, [])

      assert is_list(entities)
    end
  end

  describe "health_check/0" do
    test "returns ok for mock provider" do
      assert :ok = Mock.health_check()
    end
  end
end
