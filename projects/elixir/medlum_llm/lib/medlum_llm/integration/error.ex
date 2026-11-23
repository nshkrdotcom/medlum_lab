defmodule MedlumLlm.Integration.Error do
  @moduledoc """
  Structured error for NSAI library integration failures.

  Provides consistent error handling across all NSAI library integrations,
  making it easier to debug and handle integration-related failures.

  ## Usage

      case HfDatasetsEx.load_dataset(repo, opts) do
        {:ok, ds} -> {:ok, ds}
        {:error, reason} ->
          {:error, %MedlumLlm.Integration.Error{
            library: :hf_datasets_ex,
            operation: :load_dataset,
            reason: reason,
            context: %{repo: repo, opts: opts}
          }}
      end

  """

  @type t :: %__MODULE__{
          library: atom(),
          operation: atom(),
          reason: term(),
          context: map()
        }

  defexception [:library, :operation, :reason, :context]

  @impl true
  def message(%{library: lib, operation: op, reason: reason}) do
    "#{lib}.#{op} failed: #{inspect(reason)}"
  end
end
