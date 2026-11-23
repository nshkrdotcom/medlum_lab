defmodule MedOntology.Mapping do
  @moduledoc """
  Represents a mapping between concepts in different ontologies.

  Mappings allow translation between different medical terminologies,
  such as mapping SNOMED-CT concepts to ICD-10 codes for billing purposes.

  ## Fields

    * `:source_system` - The source ontology
    * `:source_code` - The code in the source ontology
    * `:target_system` - The target ontology
    * `:target_code` - The code in the target ontology
    * `:equivalence` - The degree of equivalence between concepts
    * `:active` - Whether the mapping is currently active

  ## Equivalence Types

    * `:equivalent` - The concepts are semantically equivalent
    * `:narrower` - The target concept is more specific than the source
    * `:broader` - The target concept is less specific than the source
    * `:related` - The concepts are related but not equivalent

  ## Examples

      iex> %MedOntology.Mapping{
      ...>   source_system: :snomed_ct,
      ...>   source_code: "44054006",
      ...>   target_system: :icd10,
      ...>   target_code: "E11.9",
      ...>   equivalence: :equivalent
      ...> }

  """

  @type equivalence :: :equivalent | :narrower | :broader | :related

  @type ontology :: :snomed_ct | :icd10 | :rxnorm | :loinc | :ndc

  @type t :: %__MODULE__{
          source_system: ontology(),
          source_code: String.t(),
          target_system: ontology(),
          target_code: String.t(),
          equivalence: equivalence(),
          active: boolean()
        }

  @enforce_keys [:source_system, :source_code, :target_system, :target_code]
  defstruct [
    :source_system,
    :source_code,
    :target_system,
    :target_code,
    equivalence: :related,
    active: true
  ]

  @doc """
  Creates a new Mapping struct.

  ## Examples

      iex> MedOntology.Mapping.new(:snomed_ct, "44054006", :icd10, "E11.9")
      %MedOntology.Mapping{
        source_system: :snomed_ct,
        source_code: "44054006",
        target_system: :icd10,
        target_code: "E11.9",
        equivalence: :related,
        active: true
      }

  """
  @spec new(ontology(), String.t(), ontology(), String.t(), keyword()) :: t()
  def new(source_system, source_code, target_system, target_code, opts \\ []) do
    %__MODULE__{
      source_system: source_system,
      source_code: source_code,
      target_system: target_system,
      target_code: target_code,
      equivalence: Keyword.get(opts, :equivalence, :related),
      active: Keyword.get(opts, :active, true)
    }
  end
end
