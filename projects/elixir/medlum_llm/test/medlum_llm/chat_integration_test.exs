defmodule MedlumLlm.ChatIntegrationTest do
  @moduledoc """
  Integration tests for chat functionality with medical LLMs.

  These tests require:
  1. Ollama running on localhost:11434
  2. At least one medical model pulled (e.g., BioMistral-7B)

  Run with: mix test --include integration
  """

  use ExUnit.Case, async: false

  alias MedlumLlm.TestHelpers

  @moduletag :integration
  @moduletag timeout: 120_000

  setup do
    case TestHelpers.skip_if_no_ollama() do
      :ok -> :ok
      skip -> skip
    end
  end

  describe "chat/2 with BioMistral" do
    @tag timeout: 120_000
    test "responds to medical questions" do
      # Skip if model not available
      case MedlumLlm.model_info(:biomistral_7b) do
        {:ok, _} ->
          {:ok, response} =
            MedlumLlm.chat(
              "What are the main symptoms of type 2 diabetes?",
              model: :biomistral_7b,
              max_tokens: 200
            )

          assert is_binary(response)
          assert String.length(response) > 50

          # Should mention common diabetes symptoms
          response_lower = String.downcase(response)

          assert String.contains?(response_lower, "thirst") or
                   String.contains?(response_lower, "urination") or
                   String.contains?(response_lower, "fatigue") or
                   String.contains?(response_lower, "glucose") or
                   String.contains?(response_lower, "sugar")

        {:error, _} ->
          IO.puts("\nSkipping: BioMistral-7B not pulled")
          :ok
      end
    end
  end

  describe "chat_messages/2" do
    @tag timeout: 120_000
    test "handles multi-turn conversation" do
      case MedlumLlm.model_info(:biomistral_7b) do
        {:ok, _} ->
          messages = [
            %{role: "user", content: "What is hypertension?"},
            %{role: "assistant", content: "Hypertension is high blood pressure."},
            %{role: "user", content: "What are the risk factors?"}
          ]

          {:ok, response} =
            MedlumLlm.chat_messages(messages,
              model: :biomistral_7b,
              max_tokens: 200
            )

          assert is_binary(response)
          assert String.length(response) > 20

        {:error, _} ->
          IO.puts("\nSkipping: BioMistral-7B not pulled")
          :ok
      end
    end
  end

  describe "complete/2" do
    @tag timeout: 120_000
    test "completes clinical text" do
      case MedlumLlm.model_info(:biomistral_7b) do
        {:ok, _} ->
          {:ok, completion} =
            MedlumLlm.Chat.complete(
              "The patient presents with acute chest pain and",
              model: :biomistral_7b
            )

          assert is_binary(completion)
          assert String.length(completion) > 10

        {:error, _} ->
          IO.puts("\nSkipping: BioMistral-7B not pulled")
          :ok
      end
    end
  end
end
