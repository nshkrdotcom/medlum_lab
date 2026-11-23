defmodule MedOntology.Client.RxNav do
  @moduledoc """
  Client for NLM RxNav API.

  Provides access to RxNorm drug concepts, classifications, and interactions.

  Base URL: https://rxnav.nlm.nih.gov/REST

  **No authentication required.** Fair use policy applies.

  ## Examples

      # Get concept by RxCUI
      MedOntology.Client.RxNav.get_concept("861004")

      # Search for drugs
      MedOntology.Client.RxNav.search("metformin")

      # Get drug interactions
      MedOntology.Client.RxNav.get_interactions(["861004", "197361"])

  ## RxNorm Term Types (TTY)

  | TTY | Description | Example |
  |-----|-------------|---------|
  | IN | Ingredient | metformin |
  | PIN | Precise Ingredient | metformin hydrochloride |
  | SCDC | Semantic Clinical Drug Component | metformin 500 MG |
  | SCD | Semantic Clinical Drug | metformin 500 MG Oral Tablet |
  | SBD | Semantic Branded Drug | Glucophage 500 MG Oral Tablet |

  """

  # Use RxNavBehaviour which includes all callbacks (base + RxNorm-specific)
  @behaviour MedOntology.Client.RxNavBehaviour

  alias MedOntology.Config

  @base_url "https://rxnav.nlm.nih.gov/REST"

  @doc """
  Get concept properties by RxCUI.

  Returns all properties for an RxNorm concept including name, synonyms,
  term type, and other metadata.

  ## Examples

      iex> MedOntology.Client.RxNav.get_concept("861004")
      {:ok, %{"propConceptGroup" => %{"propConcept" => [...]}}}

      iex> MedOntology.Client.RxNav.get_concept("invalid")
      {:error, :not_found}

  """
  @impl true
  def get_concept(rxcui) do
    url = "#{@base_url}/rxcui/#{rxcui}/allProperties.json?prop=all"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        data = Jason.decode!(body)

        if has_properties?(data) do
          {:ok, data}
        else
          {:error, :not_found}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for drugs by name string.

  Returns approximate matches with RxCUIs. Uses the /drugs endpoint
  which provides grouped results by term type.

  ## Options

    * `:limit` - Maximum results (applied after fetching)

  ## Examples

      iex> MedOntology.Client.RxNav.search("metformin")
      {:ok, [%{"rxcui" => "861004", "name" => "metformin 500 MG Oral Tablet", ...}]}

  """
  @impl true
  def search(drug_name, _opts \\ []) do
    encoded_name = URI.encode(drug_name)
    url = "#{@base_url}/drugs.json?name=#{encoded_name}"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        data = Jason.decode!(body)
        groups = get_in(data, ["drugGroup", "conceptGroup"]) || []
        concepts = Enum.flat_map(groups, fn g -> g["conceptProperties"] || [] end)
        {:ok, concepts}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get RxCUI for a drug name (exact or approximate match).

  Uses the /rxcui endpoint which is optimized for drug name normalization.
  The `search=2` parameter enables approximate matching.

  ## Examples

      iex> MedOntology.Client.RxNav.get_rxcui("metformin 500mg")
      {:ok, "861004"}

      iex> MedOntology.Client.RxNav.get_rxcui("unknown drug xyz")
      {:error, :not_found}

  """
  @impl MedOntology.Client.RxNavBehaviour
  @spec get_rxcui(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_rxcui(drug_string) do
    encoded = URI.encode(drug_string)
    # search=2 enables approximate matching
    url = "#{@base_url}/rxcui.json?name=#{encoded}&search=2"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        data = Jason.decode!(body)

        case get_in(data, ["idGroup", "rxnormId"]) do
          [rxcui | _] -> {:ok, rxcui}
          _ -> {:error, :not_found}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get drug ingredients for an RxCUI.

  Returns ingredients (IN) and precise ingredients (PIN) related to
  the given RxNorm concept.

  ## Examples

      iex> MedOntology.Client.RxNav.get_ingredients("861004")
      {:ok, [%{"rxcui" => "6809", "name" => "Metformin", "tty" => "IN"}]}

  """
  @impl MedOntology.Client.RxNavBehaviour
  @spec get_ingredients(String.t()) :: {:ok, [map()]} | {:error, term()}
  def get_ingredients(rxcui) do
    # IN = Ingredient, PIN = Precise Ingredient
    url = "#{@base_url}/rxcui/#{rxcui}/related.json?tty=IN+PIN"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        data = Jason.decode!(body)
        groups = get_in(data, ["relatedGroup", "conceptGroup"]) || []
        concepts = Enum.flat_map(groups, fn g -> g["conceptProperties"] || [] end)
        {:ok, concepts}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get drug class information.

  Supports ATC, VA, NDFRT, and other classification systems.

  ## Parameters

    * `rxcui` - The RxNorm concept identifier
    * `class_type` - Classification system: "ATC", "VA", "NDFRT" (default: "ATC")

  ## Examples

      iex> MedOntology.Client.RxNav.get_drug_class("861004", "ATC")
      {:ok, [%{"rxclassMinConceptItem" => %{"classId" => "A10BA02", ...}}]}

  """
  @impl MedOntology.Client.RxNavBehaviour
  @spec get_drug_class(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def get_drug_class(rxcui, class_type \\ "ATC") do
    url = "#{@base_url}/rxclass/class/byRxcui.json?rxcui=#{rxcui}&relaSource=#{class_type}"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        data = Jason.decode!(body)
        classes = get_in(data, ["rxclassDrugInfoList", "rxclassDrugInfo"]) || []
        {:ok, classes}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get NDC codes for an RxCUI.

  Returns National Drug Codes (11-digit format) associated with
  the given RxNorm concept.

  ## Examples

      iex> MedOntology.Client.RxNav.get_ndc("861004")
      {:ok, ["00378-0226-01", "00591-2468-01", ...]}

  """
  @impl MedOntology.Client.RxNavBehaviour
  @spec get_ndc(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def get_ndc(rxcui) do
    url = "#{@base_url}/rxcui/#{rxcui}/ndcs.json"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        data = Jason.decode!(body)
        ndcs = get_in(data, ["ndcGroup", "ndcList", "ndc"]) || []
        {:ok, ndcs}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get drug-drug interactions between RxCUIs.

  Uses the RxNorm Interaction API to check for known interactions
  between two or more medications.

  ## Examples

      iex> MedOntology.Client.RxNav.get_interactions(["861004", "197361"])
      {:ok, [%{"fullInteractionType" => [...]}]}

      iex> MedOntology.Client.RxNav.get_interactions("861004", "197361")
      {:ok, [%{"fullInteractionType" => [...]}]}

  """
  @spec get_interactions([String.t()]) :: {:ok, [map()]} | {:error, term()}
  def get_interactions(rxcui_list) when is_list(rxcui_list) do
    rxcuis = Enum.join(rxcui_list, "+")
    url = "https://rxnav.nlm.nih.gov/REST/interaction/list.json?rxcuis=#{rxcuis}"

    case http_get(url) do
      {:ok, %{status: 200, body: body}} ->
        data = Jason.decode!(body)
        interactions = get_in(data, ["fullInteractionTypeGroup"]) || []
        {:ok, interactions}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl MedOntology.Client.RxNavBehaviour
  @spec get_interactions(String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def get_interactions(rxcui1, rxcui2) do
    get_interactions([rxcui1, rxcui2])
  end

  @doc """
  Check if the RxNav API is available.

  Performs a health check by attempting to fetch the aspirin concept (RxCUI 1191).

  ## Examples

      iex> MedOntology.Client.RxNav.health_check()
      :ok

      iex> MedOntology.Client.RxNav.health_check()
      {:error, :unavailable}

  """
  @impl true
  def health_check do
    # Check with aspirin RxCUI
    url = "#{@base_url}/rxcui/1191/properties.json"

    case http_get(url) do
      {:ok, %{status: 200}} -> :ok
      _ -> {:error, :unavailable}
    end
  end

  # Private functions

  defp http_get(url) do
    headers = [{"Accept", "application/json"}]
    request = Finch.build(:get, url, headers)

    case Finch.request(request, MedOntology.Finch, receive_timeout: Config.http_timeout_ms()) do
      {:ok, %Finch.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp has_properties?(data) do
    case get_in(data, ["propConceptGroup", "propConcept"]) do
      nil -> false
      [] -> false
      _ -> true
    end
  end
end
