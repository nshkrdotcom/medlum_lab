defmodule MedOntology.Client.Snowstorm do
  @moduledoc """
  Client for SNOMED International Snowstorm API.

  Provides access to SNOMED-CT concepts, relationships, and ECL queries
  using the publicly available Snowstorm terminology server.

  ## Configuration

      config :med_ontology_ex,
        snowstorm_base_url: "https://browser.ihtsdotools.org/snowstorm/snomed-ct",
        snowstorm_branch: "MAIN/2024-09-01"

  ## Examples

      # Get a concept by SCTID
      MedOntology.Client.Snowstorm.get_concept("44054006")
      #=> {:ok, %{"conceptId" => "44054006", ...}}

      # Search for concepts
      MedOntology.Client.Snowstorm.search("diabetes", limit: 10)
      #=> {:ok, [%{"conceptId" => "73211009", ...}, ...]}

      # Execute ECL query
      MedOntology.Client.Snowstorm.ecl_query("<< 73211009")
      #=> {:ok, [%{"conceptId" => "44054006", ...}, ...]}

  """

  @behaviour MedOntology.Client

  alias MedOntology.Config

  @default_base_url "https://browser.ihtsdotools.org/snowstorm/snomed-ct"
  @default_branch "MAIN/2024-09-01"

  @doc """
  Get a concept by SCTID.

  ## Examples

      iex> MedOntology.Client.Snowstorm.get_concept("44054006")
      {:ok, %{
        "conceptId" => "44054006",
        "fsn" => %{"term" => "Diabetes mellitus type 2 (disorder)"},
        "pt" => %{"term" => "Type 2 diabetes mellitus"},
        "active" => true
      }}

      iex> MedOntology.Client.Snowstorm.get_concept("invalid")
      {:error, :not_found}

  """
  @impl true
  def get_concept(sctid) do
    url = "#{base_url()}/#{branch()}/concepts/#{sctid}"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for concepts by term.

  ## Options

    * `:limit` - Maximum results (default: 25)
    * `:semantic_tags` - Filter by semantic tags (e.g., ["disorder", "finding"])
    * `:active_only` - Only return active concepts (default: true)

  ## Examples

      iex> MedOntology.Client.Snowstorm.search("diabetes")
      {:ok, [%{"conceptId" => "73211009", ...}, ...]}

      iex> MedOntology.Client.Snowstorm.search("diabetes", semantic_tags: ["disorder"])
      {:ok, [%{"conceptId" => "73211009", ...}, ...]}

  """
  @impl true
  def search(term, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    semantic_tags = Keyword.get(opts, :semantic_tags, [])
    active_only = Keyword.get(opts, :active_only, true)

    params = %{
      "term" => term,
      "limit" => limit,
      "activeFilter" => active_only
    }

    params =
      if semantic_tags != [] do
        Map.put(params, "semanticTags", Enum.join(semantic_tags, ","))
      else
        params
      end

    query = URI.encode_query(params)
    url = "#{base_url()}/#{branch()}/concepts?#{query}"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        data = Jason.decode!(body)
        {:ok, Map.get(data, "items", [])}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get parent concepts (is-a relationships).

  Returns the immediate parents of a concept using the inferred relationship form.

  ## Examples

      iex> MedOntology.Client.Snowstorm.get_parents("44054006")
      {:ok, [%{"conceptId" => "73211009", ...}]}

  """
  @impl true
  def get_parents(sctid) do
    url = "#{base_url()}/#{branch()}/concepts/#{sctid}/parents?form=inferred"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get child concepts (subtypes).

  ## Options

    * `:limit` - Maximum results (default: 100)

  ## Examples

      iex> MedOntology.Client.Snowstorm.get_children("73211009", limit: 50)
      {:ok, [%{"conceptId" => "44054006", ...}, ...]}

  """
  @impl true
  def get_children(sctid, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    url = "#{base_url()}/#{branch()}/concepts/#{sctid}/children?form=inferred&limit=#{limit}"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Execute an ECL (Expression Constraint Language) query.

  ECL is a powerful query language for SNOMED-CT that allows you to
  express complex constraints on concepts.

  ## Examples

      # All descendants of diabetes mellitus
      iex> MedOntology.Client.Snowstorm.ecl_query("<< 73211009")
      {:ok, [%{"conceptId" => "44054006", ...}, ...]}

      # Disorders with finding site in lung
      iex> MedOntology.Client.Snowstorm.ecl_query("<< 64572001 : 363698007 = 39607008")
      {:ok, [...]}

  ## Options

    * `:limit` - Maximum results (default: 100)

  """
  @impl true
  def ecl_query(ecl, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    encoded_ecl = URI.encode(ecl)
    url = "#{base_url()}/#{branch()}/concepts?ecl=#{encoded_ecl}&limit=#{limit}"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        data = Jason.decode!(body)
        {:ok, Map.get(data, "items", [])}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get relationships for a concept.

  Returns all active relationships for the given concept, including
  is-a, finding-site, associated-morphology, and other SNOMED-CT relationships.

  ## Examples

      iex> MedOntology.Client.Snowstorm.get_relationships("44054006")
      {:ok, %{"items" => [%{"type" => %{"conceptId" => "116680003"}, ...}]}}

  """
  @impl true
  def get_relationships(sctid) do
    url = "#{base_url()}/#{branch()}/concepts/#{sctid}/relationships?active=true"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if the Snowstorm API is available.

  Performs a health check by attempting to fetch the SNOMED-CT root concept.

  ## Examples

      iex> MedOntology.Client.Snowstorm.health_check()
      :ok

      iex> MedOntology.Client.Snowstorm.health_check()
      {:error, :unavailable}

  """
  @impl true
  def health_check do
    # 138875005 is the SNOMED CT root concept "SNOMED CT Concept"
    url = "#{base_url()}/#{branch()}/concepts/138875005"

    case http_get(url) do
      {:ok, %{status: 200}} -> :ok
      _ -> {:error, :unavailable}
    end
  end

  # Private functions

  defp http_get(url) do
    headers = [
      {"Accept", "application/json"},
      {"Accept-Language", "en"}
    ]

    request = Finch.build(:get, url, headers)

    case Finch.request(request, MedOntology.Finch, receive_timeout: Config.http_timeout_ms()) do
      {:ok, %Finch.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_url do
    Application.get_env(:med_ontology_ex, :snowstorm_base_url, @default_base_url)
  end

  defp branch do
    Application.get_env(:med_ontology_ex, :snowstorm_branch, @default_branch)
  end
end
