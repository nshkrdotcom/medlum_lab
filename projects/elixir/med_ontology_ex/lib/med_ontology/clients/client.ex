defmodule MedOntology.Client do
  @moduledoc """
  Behaviour for external API clients.

  All ontology API clients must implement this behaviour to ensure
  consistent interfaces across different data sources.

  ## Implementing a Client

      defmodule MedOntology.Client.MyClient do
        @behaviour MedOntology.Client

        @impl true
        def get_concept(code) do
          # Fetch concept from external API
          {:ok, %{"code" => code, "name" => "..."}}
        end

        @impl true
        def search(query, opts \\\\ []) do
          # Search for concepts
          {:ok, [%{"code" => "123", "name" => "..."}]}
        end

        @impl true
        def health_check do
          # Check if the API is reachable
          :ok
        end
      end

  """

  @doc """
  Fetches a concept by its code from the external API.

  Returns `{:ok, map()}` with the raw API response data on success,
  or `{:error, term()}` on failure.

  ## Examples

      iex> MyClient.get_concept("44054006")
      {:ok, %{"conceptId" => "44054006", "fsn" => "..."}}

      iex> MyClient.get_concept("invalid")
      {:error, :not_found}

  """
  @callback get_concept(code :: String.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Searches for concepts matching the given query.

  Returns `{:ok, [map()]}` with a list of raw API response data on success,
  or `{:error, term()}` on failure.

  ## Options

    * `:limit` - Maximum number of results (default: 25)
    * `:offset` - Number of results to skip (default: 0)

  ## Examples

      iex> MyClient.search("diabetes")
      {:ok, [%{"code" => "44054006", "name" => "Type 2 diabetes mellitus"}]}

  """
  @callback search(query :: String.t(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Performs a health check on the external API.

  Returns `:ok` if the API is reachable and responding,
  or `{:error, term()}` if there's an issue.

  ## Examples

      iex> MyClient.health_check()
      :ok

      iex> MyClient.health_check()
      {:error, :timeout}

  """
  @callback health_check() :: :ok | {:error, term()}

  @doc """
  Optional callback for getting hierarchical relationships.

  Returns parent or child concepts for a given code.
  """
  @callback get_hierarchy(code :: String.t(), direction :: :parents | :children, opts :: keyword()) ::
              {:ok, [map()]} | {:error, term()}

  @doc """
  Optional callback for getting parent concepts.

  Returns parent concepts for a given code.
  """
  @callback get_parents(code :: String.t()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Optional callback for getting child concepts.

  Returns child concepts for a given code.
  """
  @callback get_children(code :: String.t(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Optional callback for getting relationships for a concept.

  Returns all relationships for the given concept.
  """
  @callback get_relationships(code :: String.t()) :: {:ok, map()} | {:error, term()}

  @doc """
  Optional callback for executing ECL queries (SNOMED-CT specific).

  Returns concepts matching the ECL expression.
  """
  @callback ecl_query(ecl :: String.t(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}

  @optional_callbacks [
    get_hierarchy: 3,
    get_parents: 1,
    get_children: 2,
    get_relationships: 1,
    ecl_query: 2
  ]
end
