defmodule MedOntology.Client.LOINC do
  @moduledoc """
  Client for LOINC FHIR Terminology Service.

  Base URL: https://fhir.loinc.org
  Authentication: HTTP Basic Auth with loinc.org credentials

  ## Configuration

      config :med_ontology_ex,
        loinc_username: "your-username",
        loinc_password: "your-password"

  ## Note

  This service is in BETA status. API may change.

  ## Examples

      # Get a LOINC concept
      MedOntology.Client.LOINC.get_concept("2345-7")

      # Search for codes
      MedOntology.Client.LOINC.search("glucose")

      # Get panel members
      MedOntology.Client.LOINC.get_panel_members("24323-8")

  """

  @behaviour MedOntology.Client.LOINCBehaviour

  alias MedOntology.Config

  @base_url "https://fhir.loinc.org"

  @doc """
  Get a LOINC concept using CodeSystem/$lookup.

  ## Examples

      iex> MedOntology.Client.LOINC.get_concept("2345-7")
      {:ok, %{
        "display" => "Glucose [Mass/volume] in Serum or Plasma",
        "COMPONENT" => "Glucose",
        "PROPERTY" => "MCnc",
        ...
      }}

      iex> MedOntology.Client.LOINC.get_concept("invalid")
      {:error, :not_found}

  """
  @impl true
  @spec get_concept(String.t()) :: {:ok, map()} | {:error, term()}
  def get_concept(loinc_code) do
    url = "#{@base_url}/CodeSystem/$lookup?system=http://loinc.org&code=#{loinc_code}"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_fhir_parameters(body)}

      {:ok, %{status: 401}} ->
        {:error, :authentication_required}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search LOINC codes by term.

  Uses the FHIR CodeSystem search with name:contains filter.

  ## Options

    * `:limit` - Maximum results (default: 25)

  ## Examples

      iex> MedOntology.Client.LOINC.search("hemoglobin")
      {:ok, [%{"code" => "718-7", "display" => "Hemoglobin [Mass/volume] in Blood"}, ...]}

  """
  @impl true
  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(term, opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    encoded_term = URI.encode(term)

    url = "#{@base_url}/CodeSystem/$lookup?system=http://loinc.org&_filter=name:contains=#{encoded_term}&_count=#{limit}"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_search_results(body)}

      {:ok, %{status: 401}} ->
        {:error, :authentication_required}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get panel members using ValueSet/$expand.

  ## Examples

      iex> MedOntology.Client.LOINC.get_panel_members("24323-8")
      {:ok, [%{"code" => "2345-7", "display" => "Glucose"}, ...]}

  """
  @impl true
  @spec get_panel_members(String.t()) :: {:ok, [map()]} | {:error, term()}
  def get_panel_members(panel_code) do
    url = "#{@base_url}/ValueSet/$expand?url=http://loinc.org/vs/#{panel_code}"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_valueset_expansion(body)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 401}} ->
        {:error, :authentication_required}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if the LOINC FHIR API is available.

  Performs a health check by attempting to fetch a common LOINC code (Glucose).

  ## Examples

      iex> MedOntology.Client.LOINC.health_check()
      :ok

      iex> MedOntology.Client.LOINC.health_check()
      {:error, :authentication_required}

  """
  @impl true
  @spec health_check() :: :ok | {:error, term()}
  def health_check do
    # Try to look up a common LOINC code (Glucose)
    url = "#{@base_url}/CodeSystem/$lookup?system=http://loinc.org&code=2345-7"

    case http_get(url) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: 401}} -> {:error, :authentication_required}
      _ -> {:error, :unavailable}
    end
  end

  # Private functions

  defp http_get(url) do
    headers = auth_headers()
    request = Finch.build(:get, url, headers)

    case Finch.request(request, MedOntology.Finch, receive_timeout: Config.http_timeout_ms()) do
      {:ok, %Finch.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp auth_headers do
    username = Config.loinc_username()
    password = Config.loinc_password()

    base_headers = [{"Accept", "application/fhir+json"}]

    if username && password do
      credentials = Base.encode64("#{username}:#{password}")
      [{"Authorization", "Basic #{credentials}"} | base_headers]
    else
      base_headers
    end
  end

  defp parse_fhir_parameters(body) do
    data = Jason.decode!(body)

    (data["parameter"] || [])
    |> Enum.reduce(%{}, fn param, acc ->
      name = param["name"]

      value =
        param["valueString"] ||
          param["valueCode"] ||
          extract_coding_value(param["valueCoding"]) ||
          extract_part_value(param["part"])

      if value do
        Map.put(acc, name, value)
      else
        acc
      end
    end)
  end

  defp extract_coding_value(nil), do: nil

  defp extract_coding_value(coding) when is_map(coding) do
    coding["display"] || coding["code"]
  end

  defp extract_part_value(nil), do: nil

  defp extract_part_value(parts) when is_list(parts) do
    # Handle nested part structures in FHIR Parameters
    parts
    |> Enum.map(fn part ->
      {part["name"], part["valueString"] || part["valueCode"]}
    end)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp parse_search_results(body) do
    data = Jason.decode!(body)

    # FHIR search results come as a Bundle
    case data["entry"] do
      nil ->
        # Try parsing as Parameters response
        parse_fhir_parameters(body)
        |> case do
          params when is_map(params) and map_size(params) > 0 ->
            [params]

          _ ->
            []
        end

      entries when is_list(entries) ->
        Enum.map(entries, fn entry ->
          resource = entry["resource"]

          %{
            "code" => resource["id"] || resource["code"],
            "display" => resource["name"] || resource["display"]
          }
        end)
    end
  end

  defp parse_valueset_expansion(body) do
    data = Jason.decode!(body)

    get_in(data, ["expansion", "contains"]) || []
  end
end
