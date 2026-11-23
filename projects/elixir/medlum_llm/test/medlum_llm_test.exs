defmodule MedlumLlmTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.TestHelpers

  describe "cosine_similarity/2" do
    test "returns 1.0 for identical vectors" do
      vec = [1.0, 2.0, 3.0]
      assert_in_delta MedlumLlm.cosine_similarity(vec, vec), 1.0, 0.0001
    end

    test "returns 0.0 for orthogonal vectors" do
      vec1 = [1.0, 0.0, 0.0]
      vec2 = [0.0, 1.0, 0.0]
      assert_in_delta MedlumLlm.cosine_similarity(vec1, vec2), 0.0, 0.0001
    end

    test "returns -1.0 for opposite vectors" do
      vec1 = [1.0, 2.0, 3.0]
      vec2 = [-1.0, -2.0, -3.0]
      assert_in_delta MedlumLlm.cosine_similarity(vec1, vec2), -1.0, 0.0001
    end

    test "handles zero vectors" do
      vec1 = [0.0, 0.0, 0.0]
      vec2 = [1.0, 2.0, 3.0]
      assert MedlumLlm.cosine_similarity(vec1, vec2) == 0.0
    end

    test "handles high-dimensional vectors" do
      vec = TestHelpers.generate_fake_embedding(768)

      result = MedlumLlm.cosine_similarity(vec, vec)
      assert_in_delta result, 1.0, 0.0001
    end
  end

  describe "supported_models/0" do
    test "returns all model definitions" do
      models = MedlumLlm.supported_models()

      assert is_map(models)
      assert Map.has_key?(models, :biomistral_7b)
      assert Map.has_key?(models, :openbio_8b)
      assert Map.has_key?(models, :meditron_7b)
      assert Map.has_key?(models, :nomic_embed)
    end

    test "each model has required fields" do
      models = MedlumLlm.supported_models()

      Enum.each(models, fn {_key, model} ->
        assert Map.has_key?(model, :name)
        assert Map.has_key?(model, :type)
        assert Map.has_key?(model, :fits_16gb)
        assert model.type in [:chat, :embed]
      end)
    end
  end
end
