defmodule MedOntology.Client.LOINCBehaviour do
  @moduledoc """
  Behaviour for LOINC API clients.

  Extends the base `MedOntology.Client` behaviour with LOINC-specific
  callbacks for panel member retrieval.

  ## Implementing the Behaviour

      defmodule MedOntology.Client.MyLOINCClient do
        @behaviour MedOntology.Client.LOINCBehaviour

        @impl true
        def get_concept(code) do
          # Fetch LOINC concept
          {:ok, %{"display" => "...", "COMPONENT" => "..."}}
        end

        @impl true
        def search(query, opts \\\\ []) do
          # Search LOINC codes
          {:ok, [%{"code" => "2345-7", "display" => "Glucose"}]}
        end

        @impl true
        def health_check do
          :ok
        end

        @impl true
        def get_panel_members(panel_code) do
          # Get panel component codes
          {:ok, [%{"code" => "2345-7", "display" => "Glucose"}]}
        end
      end

  """

  # Include all callbacks from base Client behaviour
  @callback get_concept(code :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback search(query :: String.t(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback health_check() :: :ok | {:error, term()}

  @doc """
  Gets panel member codes for a LOINC panel.

  Returns component codes that make up a laboratory panel.

  ## Examples

      iex> MyClient.get_panel_members("24323-8")
      {:ok, [%{"code" => "2345-7", "display" => "Glucose"}, ...]}

  """
  @callback get_panel_members(panel_code :: String.t()) :: {:ok, [map()]} | {:error, term()}
end
