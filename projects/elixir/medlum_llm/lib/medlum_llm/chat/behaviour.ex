defmodule MedlumLlm.Chat.Behaviour do
  @moduledoc """
  Behaviour for chat/text generation backends.
  """

  @callback chat(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback chat_messages([map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback chat_stream(String.t(), (String.t() -> any()), keyword()) :: :ok | {:error, term()}
  @callback complete(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
