defmodule MedOntology.Mapper do
  @moduledoc """
  Cross-ontology mapping coordinator.

  Handles mappings between different medical ontologies, such as:
    * SNOMED-CT to ICD-10
    * ICD-10 to SNOMED-CT
    * RxNorm to NDC

  ## Usage

      # Map SNOMED-CT to ICD-10
      MedOntology.Mapper.map(:snomed_ct, "44054006", :icd10)
      #=> {:ok, [%Mapping{target_code: "E11.9", equivalence: :equivalent}]}

      # Get all mappings for a concept
      MedOntology.Mapper.all_mappings(:snomed_ct, "44054006")
      #=> {:ok, %{icd10: [%Mapping{...}]}}

  ## Supported Mappings

    * `:snomed_ct` -> `:icd10` - Uses NLM SNOMED-CT to ICD-10-CM map
    * `:icd10` -> `:snomed_ct` - Reverse mapping
    * `:rxnorm` -> `:ndc` - RxNorm to National Drug Codes

  """

  alias MedOntology.Mapping

  @doc """
  Maps a concept from one ontology to another.

  ## Examples

      iex> MedOntology.Mapper.map(:snomed_ct, "44054006", :icd10)
      {:ok, [%Mapping{
        source_system: :snomed_ct,
        source_code: "44054006",
        target_system: :icd10,
        target_code: "E11.9",
        equivalence: :equivalent
      }]}

  """
  @spec map(atom(), String.t(), atom()) ::
          {:ok, [Mapping.t()]} | {:error, :unsupported_mapping | term()}
  def map(from_ontology, code, to_ontology) do
    case {from_ontology, to_ontology} do
      {:snomed_ct, :icd10} ->
        map_snomed_to_icd10(code)

      {:icd10, :snomed_ct} ->
        map_icd10_to_snomed(code)

      {:rxnorm, :ndc} ->
        map_rxnorm_to_ndc(code)

      {from, to} ->
        {:error, {:unsupported_mapping, from, to}}
    end
  end

  @doc """
  Gets all available mappings for a concept across all ontologies.

  ## Examples

      iex> MedOntology.Mapper.all_mappings(:snomed_ct, "44054006")
      {:ok, %{
        icd10: [%Mapping{target_code: "E11.9", ...}]
      }}

  """
  @spec all_mappings(atom(), String.t()) ::
          {:ok, %{atom() => [Mapping.t()]}} | {:error, term()}
  def all_mappings(from_ontology, code) do
    target_ontologies = target_ontologies_for(from_ontology)

    results =
      Enum.reduce(target_ontologies, %{}, fn to_ontology, acc ->
        case map(from_ontology, code, to_ontology) do
          {:ok, mappings} when mappings != [] ->
            Map.put(acc, to_ontology, mappings)

          _ ->
            acc
        end
      end)

    {:ok, results}
  end

  # Private implementation

  defp map_snomed_to_icd10(sctid) do
    # First check cache
    case MedOntology.Cache.Server.get(:snomed_to_icd10, sctid) do
      {:ok, mappings} ->
        {:ok, mappings}

      :miss ->
        # TODO: Fetch from UMLS API
        # For now, return not implemented
        {:error, :not_implemented}
    end
  end

  defp map_icd10_to_snomed(code) do
    # TODO: Implement reverse mapping
    _code = code
    {:error, :not_implemented}
  end

  defp map_rxnorm_to_ndc(rxcui) do
    # First check cache
    case MedOntology.Cache.Server.get(:rxnorm_to_ndc, rxcui) do
      {:ok, mappings} ->
        {:ok, mappings}

      :miss ->
        # TODO: Fetch from RxNav API
        {:error, :not_implemented}
    end
  end

  defp target_ontologies_for(:snomed_ct), do: [:icd10]
  defp target_ontologies_for(:icd10), do: [:snomed_ct]
  defp target_ontologies_for(:rxnorm), do: [:ndc]
  defp target_ontologies_for(_), do: []
end
