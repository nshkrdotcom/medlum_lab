defmodule MedlumLlm.IntegrationTest do
  @moduledoc """
  Integration tests that require a running Ollama instance.

  Run with: mix test --include integration
  """

  use ExUnit.Case, async: false

  alias MedlumLlm.TestHelpers

  @moduletag :integration

  setup do
    case TestHelpers.skip_if_no_ollama() do
      :ok -> :ok
      skip -> skip
    end
  end

  describe "health_check/0" do
    test "returns :ok when Ollama is running" do
      assert :ok = MedlumLlm.health_check()
    end
  end

  describe "list_models/0" do
    test "returns list of available models" do
      {:ok, models} = MedlumLlm.list_models()
      assert is_list(models)
    end
  end

  describe "embed/2 with nomic-embed-text" do
    @tag timeout: 60_000
    test "generates embeddings for clinical text" do
      {:ok, embedding} = MedlumLlm.embed("Patient presents with acute chest pain")

      assert is_list(embedding)
      assert length(embedding) > 0
      assert Enum.all?(embedding, &is_float/1)
    end

    @tag timeout: 60_000
    test "generates consistent embeddings" do
      text = "myocardial infarction"

      {:ok, emb1} = MedlumLlm.embed(text)
      {:ok, emb2} = MedlumLlm.embed(text)

      # Same text should produce identical embeddings
      similarity = MedlumLlm.cosine_similarity(emb1, emb2)
      assert_in_delta similarity, 1.0, 0.001
    end
  end

  describe "embed_batch/2" do
    @tag timeout: 60_000
    test "generates embeddings for multiple texts" do
      texts = TestHelpers.sample_clinical_notes() |> Enum.take(3)

      {:ok, embeddings} = MedlumLlm.embed_batch(texts)

      assert length(embeddings) == 3
      assert Enum.all?(embeddings, &is_list/1)
    end
  end

  describe "similarity/3" do
    @tag timeout: 60_000
    test "similar medical terms have high similarity" do
      {:ok, sim} = MedlumLlm.similarity("heart attack", "myocardial infarction")

      # These are synonymous medical terms
      assert sim > 0.5
    end

    @tag timeout: 60_000
    test "unrelated terms have lower similarity" do
      {:ok, sim_related} = MedlumLlm.similarity("chest pain", "heart attack")
      {:ok, sim_unrelated} = MedlumLlm.similarity("chest pain", "broken leg")

      # Related concepts should be more similar than unrelated
      assert sim_related > sim_unrelated
    end

    @tag timeout: 60_000
    test "identical terms have similarity close to 1.0" do
      {:ok, sim} = MedlumLlm.similarity("diabetes mellitus", "diabetes mellitus")
      assert_in_delta sim, 1.0, 0.001
    end
  end
end
