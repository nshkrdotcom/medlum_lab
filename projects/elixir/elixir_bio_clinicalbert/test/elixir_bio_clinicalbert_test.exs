defmodule ElixirBioClinicalbertTest do
  use ExUnit.Case, async: true

  import Mox

  # Allow mock to be called from any process
  setup :verify_on_exit!

  setup do
    # Configure to use mock embedder for tests
    Application.put_env(:elixir_bio_clinicalbert, :embedder, ElixirBioClinicalbert.EmbedderMock)

    on_exit(fn ->
      Application.delete_env(:elixir_bio_clinicalbert, :embedder)
    end)

    :ok
  end

  describe "embed/2" do
    test "returns embeddings for clinical text" do
      expected_embedding = generate_fake_embedding(768)

      ElixirBioClinicalbert.EmbedderMock
      |> expect(:embed, fn "Patient has chest pain", _opts ->
        {:ok, expected_embedding}
      end)

      assert {:ok, embedding} = ElixirBioClinicalbert.embed("Patient has chest pain")
      assert length(embedding) == 768
      assert Enum.all?(embedding, &is_float/1)
    end

    test "propagates errors from embedder" do
      ElixirBioClinicalbert.EmbedderMock
      |> expect(:embed, fn _text, _opts ->
        {:error, :model_not_found}
      end)

      assert {:error, :model_not_found} = ElixirBioClinicalbert.embed("test")
    end

    test "handles empty text" do
      expected_embedding = generate_fake_embedding(768)

      ElixirBioClinicalbert.EmbedderMock
      |> expect(:embed, fn "", _opts ->
        {:ok, expected_embedding}
      end)

      assert {:ok, _embedding} = ElixirBioClinicalbert.embed("")
    end
  end

  describe "embed_batch/2" do
    test "returns embeddings for multiple clinical texts" do
      texts = [
        "acute myocardial infarction",
        "normal sinus rhythm",
        "elevated troponin levels"
      ]

      expected_embeddings = Enum.map(texts, fn _ -> generate_fake_embedding(768) end)

      ElixirBioClinicalbert.EmbedderMock
      |> expect(:embed_batch, fn ^texts, _opts ->
        {:ok, expected_embeddings}
      end)

      assert {:ok, embeddings} = ElixirBioClinicalbert.embed_batch(texts)
      assert length(embeddings) == 3
      assert Enum.all?(embeddings, fn emb -> length(emb) == 768 end)
    end

    test "handles empty list" do
      ElixirBioClinicalbert.EmbedderMock
      |> expect(:embed_batch, fn [], _opts ->
        {:ok, []}
      end)

      assert {:ok, []} = ElixirBioClinicalbert.embed_batch([])
    end
  end

  describe "similarity/3" do
    test "calculates similarity between similar clinical terms" do
      # "heart attack" and "myocardial infarction" are clinically synonymous
      # Their embeddings should be similar (high cosine similarity)
      emb1 = [0.5, 0.5, 0.5, 0.5]
      emb2 = [0.6, 0.5, 0.5, 0.4]

      ElixirBioClinicalbert.EmbedderMock
      |> expect(:embed, fn "heart attack", _opts -> {:ok, emb1} end)
      |> expect(:embed, fn "myocardial infarction", _opts -> {:ok, emb2} end)

      assert {:ok, similarity} =
               ElixirBioClinicalbert.similarity("heart attack", "myocardial infarction")

      # Should be relatively high similarity
      assert similarity > 0.9
    end

    test "calculates low similarity for unrelated terms" do
      # Orthogonal vectors have 0 similarity
      emb1 = [1.0, 0.0, 0.0, 0.0]
      emb2 = [0.0, 1.0, 0.0, 0.0]

      ElixirBioClinicalbert.EmbedderMock
      |> expect(:embed, fn "diabetes", _opts -> {:ok, emb1} end)
      |> expect(:embed, fn "fracture", _opts -> {:ok, emb2} end)

      assert {:ok, similarity} = ElixirBioClinicalbert.similarity("diabetes", "fracture")
      assert_in_delta similarity, 0.0, 0.001
    end

    test "returns 1.0 for identical texts" do
      emb = [0.5, 0.5, 0.5, 0.5]

      ElixirBioClinicalbert.EmbedderMock
      |> expect(:embed, 2, fn "chest pain", _opts -> {:ok, emb} end)

      assert {:ok, similarity} = ElixirBioClinicalbert.similarity("chest pain", "chest pain")
      assert_in_delta similarity, 1.0, 0.001
    end

    test "propagates embedding errors" do
      ElixirBioClinicalbert.EmbedderMock
      |> expect(:embed, fn _text, _opts -> {:error, :connection_refused} end)

      assert {:error, :connection_refused} =
               ElixirBioClinicalbert.similarity("text1", "text2")
    end
  end

  describe "health_check/1" do
    test "returns :ok when service is healthy" do
      ElixirBioClinicalbert.EmbedderMock
      |> expect(:health_check, fn _opts -> :ok end)

      assert :ok = ElixirBioClinicalbert.health_check()
    end

    test "returns error when service is unavailable" do
      ElixirBioClinicalbert.EmbedderMock
      |> expect(:health_check, fn _opts -> {:error, :econnrefused} end)

      assert {:error, :econnrefused} = ElixirBioClinicalbert.health_check()
    end
  end

  describe "model_info/1" do
    test "returns model information" do
      expected_info = %{
        name: "nomic-embed-text",
        parameters: %{},
        template: nil,
        details: %{"family" => "nomic-bert"}
      }

      ElixirBioClinicalbert.EmbedderMock
      |> expect(:model_info, fn _opts -> {:ok, expected_info} end)

      assert {:ok, info} = ElixirBioClinicalbert.model_info()
      assert info.name == "nomic-embed-text"
    end
  end

  describe "cosine_similarity/2" do
    test "returns 1.0 for identical vectors" do
      vec = [1.0, 2.0, 3.0]
      assert_in_delta ElixirBioClinicalbert.cosine_similarity(vec, vec), 1.0, 0.0001
    end

    test "returns 0.0 for orthogonal vectors" do
      vec1 = [1.0, 0.0, 0.0]
      vec2 = [0.0, 1.0, 0.0]
      assert_in_delta ElixirBioClinicalbert.cosine_similarity(vec1, vec2), 0.0, 0.0001
    end

    test "returns -1.0 for opposite vectors" do
      vec1 = [1.0, 2.0, 3.0]
      vec2 = [-1.0, -2.0, -3.0]
      assert_in_delta ElixirBioClinicalbert.cosine_similarity(vec1, vec2), -1.0, 0.0001
    end

    test "handles zero vectors" do
      vec1 = [0.0, 0.0, 0.0]
      vec2 = [1.0, 2.0, 3.0]
      assert ElixirBioClinicalbert.cosine_similarity(vec1, vec2) == 0.0
    end
  end

  # Helper to generate fake embeddings
  defp generate_fake_embedding(dimensions) do
    :rand.seed(:exsss, {1, 2, 3})
    Enum.map(1..dimensions, fn _ -> :rand.uniform() - 0.5 end)
  end
end
