defmodule MedOntology.Client.WHO do
  @moduledoc """
  Client for WHO ICD API.

  Provides access to international ICD-10 and ICD-11 classifications from the
  World Health Organization.

  ## Configuration

  Configure the client in your `config.exs`:

      config :med_ontology_ex,
        who_client_id: "your-client-id",
        who_client_secret: "your-client-secret"

  Or via environment variables:

      config :med_ontology_ex,
        who_client_id: System.get_env("WHO_CLIENT_ID"),
        who_client_secret: System.get_env("WHO_CLIENT_SECRET")

  ## Authentication

  The WHO ICD API uses OAuth2 client credentials flow. This client handles
  token acquisition and caching automatically.

  ## Note

  This client is optional. The primary ICD-10-CM data source is CMS files.
  Use this client for:
  - International ICD-10 lookups (non-US)
  - ICD-11 support (future)
  - Validation against authoritative WHO source

  ## Examples

      # Get a concept
      MedOntology.Client.WHO.get_concept("E11.9")
      #=> {:ok, %{"title" => %{"@value" => "Type 2 diabetes mellitus"}, ...}}

      # Search for concepts
      MedOntology.Client.WHO.search("diabetes", limit: 10)
      #=> {:ok, [%{"title" => "...", ...}, ...]}

  """

  @behaviour MedOntology.Client

  alias MedOntology.Config

  @base_url "https://id.who.int/icd"
  @token_url "https://icdaccessmanagement.who.int/connect/token"

  # Token cache using process dictionary (simple approach)
  # In production, consider using ETS or a dedicated cache
  @token_cache_key :who_api_token

  @doc """
  Fetches an ICD concept by its code.

  ## Options

    * `:version` - ICD-10 version (default: "2019-1")

  ## Examples

      iex> MedOntology.Client.WHO.get_concept("E11.9")
      {:ok, %{"title" => %{"@value" => "Type 2 diabetes mellitus"}, ...}}

      iex> MedOntology.Client.WHO.get_concept("INVALID")
      {:error, :not_found}

  """
  @impl true
  def get_concept(code, opts \\ []) do
    version = Keyword.get(opts, :version, "2019-1")

    with {:ok, token} <- get_access_token() do
      url = "#{@base_url}/release/10/#{version}/#{normalize_code(code)}"
      headers = auth_headers(token)

      case http_get(url, headers) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, Jason.decode!(body)}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: 401}} ->
          # Token expired, clear cache and retry once
          clear_token_cache()
          retry_get_concept(code, opts)

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Searches for ICD concepts matching the query.

  ## Options

    * `:limit` - Maximum number of results (default: 25)
    * `:version` - ICD-10 version (default: "2019-1")

  ## Examples

      iex> MedOntology.Client.WHO.search("diabetes mellitus", limit: 10)
      {:ok, [%{"title" => "...", "theCode" => "E11", ...}, ...]}

  """
  @impl true
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    version = Keyword.get(opts, :version, "2019-1")

    with {:ok, token} <- get_access_token() do
      encoded_query = URI.encode(query)
      url = "#{@base_url}/release/10/#{version}/search?q=#{encoded_query}&flatResults=true&useFlexisearch=true&propertiesToBeSearched=Title,FullySpecifiedName&highlightingEnabled=false"

      headers = auth_headers(token)

      case http_get(url, headers) do
        {:ok, %{status: 200, body: body}} ->
          data = Jason.decode!(body)
          results = Map.get(data, "destinationEntities", [])
          {:ok, Enum.take(results, limit)}

        {:ok, %{status: 401}} ->
          clear_token_cache()
          retry_search(query, opts)

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Performs a health check on the WHO ICD API.

  Returns `:ok` if the API is reachable and credentials are valid.

  ## Examples

      iex> MedOntology.Client.WHO.health_check()
      :ok

      iex> MedOntology.Client.WHO.health_check()
      {:error, :credentials_not_configured}

  """
  @impl true
  def health_check do
    case get_access_token() do
      {:ok, _token} -> :ok
      error -> error
    end
  end

  @doc """
  Gets child concepts for a given code (not fully supported by WHO API).

  This is a stub implementation. The WHO API has limited hierarchy support.
  """
  @impl true
  def get_children(_code, _opts \\ []) do
    {:error, :not_supported}
  end

  @doc """
  Gets parent concepts for a given code (not fully supported by WHO API).

  This is a stub implementation. The WHO API has limited hierarchy support.
  """
  @impl true
  def get_parents(_code) do
    {:error, :not_supported}
  end

  # Private functions

  defp get_access_token do
    # Check cache first
    case get_cached_token() do
      {:ok, token} ->
        {:ok, token}

      :miss ->
        fetch_and_cache_token()
    end
  end

  defp get_cached_token do
    case Process.get(@token_cache_key) do
      {token, expires_at} when is_binary(token) ->
        if System.system_time(:second) < expires_at do
          {:ok, token}
        else
          :miss
        end

      _ ->
        :miss
    end
  end

  defp fetch_and_cache_token do
    client_id = Config.who_client_id()
    client_secret = Config.who_client_secret()

    if is_nil(client_id) or is_nil(client_secret) do
      {:error, :credentials_not_configured}
    else
      body =
        URI.encode_query(%{
          "client_id" => client_id,
          "client_secret" => client_secret,
          "grant_type" => "client_credentials",
          "scope" => "icdapi_access"
        })

      headers = [{"content-type", "application/x-www-form-urlencoded"}]

      case http_post(@token_url, body, headers) do
        {:ok, %{status: 200, body: response_body}} ->
          data = Jason.decode!(response_body)
          token = data["access_token"]
          # Cache token with buffer before expiry (expires_in is in seconds)
          expires_in = Map.get(data, "expires_in", 3600)
          expires_at = System.system_time(:second) + expires_in - 60

          Process.put(@token_cache_key, {token, expires_at})
          {:ok, token}

        {:ok, %{status: status, body: response_body}} ->
          {:error, {:auth_failed, status, response_body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp clear_token_cache do
    Process.delete(@token_cache_key)
  end

  defp retry_get_concept(code, opts) do
    with {:ok, token} <- get_access_token() do
      version = Keyword.get(opts, :version, "2019-1")
      url = "#{@base_url}/release/10/#{version}/#{normalize_code(code)}"
      headers = auth_headers(token)

      case http_get(url, headers) do
        {:ok, %{status: 200, body: body}} -> {:ok, Jason.decode!(body)}
        {:ok, %{status: 404}} -> {:error, :not_found}
        {:ok, %{status: status, body: body}} -> {:error, {:api_error, status, body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp retry_search(query, opts) do
    with {:ok, token} <- get_access_token() do
      limit = Keyword.get(opts, :limit, 25)
      version = Keyword.get(opts, :version, "2019-1")
      encoded_query = URI.encode(query)
      url = "#{@base_url}/release/10/#{version}/search?q=#{encoded_query}&flatResults=true&useFlexisearch=true"

      headers = auth_headers(token)

      case http_get(url, headers) do
        {:ok, %{status: 200, body: body}} ->
          data = Jason.decode!(body)
          results = Map.get(data, "destinationEntities", [])
          {:ok, Enum.take(results, limit)}

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp auth_headers(token) do
    [
      {"Authorization", "Bearer #{token}"},
      {"Accept", "application/json"},
      {"API-Version", "v2"},
      {"Accept-Language", "en"}
    ]
  end

  defp normalize_code(code) do
    # WHO API uses format like "E11.9" but URLs need encoding
    code
    |> String.upcase()
    |> URI.encode()
  end

  defp http_get(url, headers) do
    request = Finch.build(:get, url, headers)

    case Finch.request(request, MedOntology.Finch, receive_timeout: Config.http_timeout_ms()) do
      {:ok, %Finch.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_post(url, body, headers) do
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, MedOntology.Finch, receive_timeout: Config.http_timeout_ms()) do
      {:ok, %Finch.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
