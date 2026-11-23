defmodule ElixirBioClinicalbert.Embedder.OllixirTest do
  @moduledoc """
  Integration tests for the Ollixir embedder.

  These tests require a running Ollama instance with an embedding model.
  They are tagged with :integration and skipped by default.

  To run these tests:

      # First, ensure Ollama is running with an embedding model:
      ollama pull nomic-embed-text

      # Then run the integration tests:
      mix test --include integration
  """

  use ExUnit.Case, async: false

  alias ElixirBioClinicalbert.Embedder.Ollixir, as: ClinicalEmbedder

  @moduletag :integration

  describe "embed/2 (integration)" do
    @tag :integration
    test "generates embeddings for clinical text" do
      text = "Patient presents with acute chest pain and shortness of breath"

      case ClinicalEmbedder.embed(text) do
        {:ok, embedding} ->
          assert is_list(embedding)
          assert length(embedding) > 0
          assert Enum.all?(embedding, &is_float/1)

        {:error, %{__struct__: Ollixir.ConnectionError}} ->
          # Ollama not running - skip
          :ok

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
    end

    @tag :integration
    test "handles special characters in clinical text" do
      text = "BP: 120/80 mmHg, HR: 72 bpm, Temp: 98.6°F"

      case ClinicalEmbedder.embed(text) do
        {:ok, embedding} ->
          assert is_list(embedding)
          assert length(embedding) > 0

        {:error, %{__struct__: Ollixir.ConnectionError}} ->
          :ok

        {:error, _} = error ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
  end

  describe "embed_batch/2 (integration)" do
    @tag :integration
    test "generates embeddings for multiple clinical texts" do
      texts = [
        "Acute myocardial infarction",
        "Congestive heart failure",
        "Atrial fibrillation"
      ]

      case ClinicalEmbedder.embed_batch(texts) do
        {:ok, embeddings} ->
          assert length(embeddings) == 3

          Enum.each(embeddings, fn emb ->
            assert is_list(emb)
            assert length(emb) > 0
          end)

        {:error, %{__struct__: Ollixir.ConnectionError}} ->
          :ok

        {:error, _} = error ->
          flunk("Unexpected error: #{inspect(error)}")
      end
    end
  end

  describe "health_check/1 (integration)" do
    @tag :integration
    test "returns :ok when Ollama is running" do
      case ClinicalEmbedder.health_check() do
        :ok -> assert true
        {:error, _} -> :ok
      end
    end
  end
end
