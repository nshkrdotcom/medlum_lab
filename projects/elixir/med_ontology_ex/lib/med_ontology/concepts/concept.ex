defmodule MedOntology.Concept do
  @moduledoc """
  Represents a concept from any medical ontology.

  This struct provides a unified representation of concepts from SNOMED-CT,
  ICD-10, RxNorm, and LOINC ontologies.

  ## Fields

    * `:code` - The primary identifier (SCTID, ICD-10 code, RxCUI, or LOINC code)
    * `:system` - The source ontology (`:snomed_ct`, `:icd10`, `:rxnorm`, or `:loinc`)
    * `:display` - The preferred display name
    * `:fully_specified_name` - The unambiguous fully specified name (mainly SNOMED-CT)
    * `:synonyms` - Alternative names for the concept
    * `:active` - Whether the concept is currently active (not retired)
    * `:semantic_types` - Categories of the concept (e.g., "disorder", "finding")
    * `:properties` - Ontology-specific additional properties
    * `:effective_time` - When the concept became effective

  ## Examples

      iex> %MedOntology.Concept{
      ...>   code: "44054006",
      ...>   system: :snomed_ct,
      ...>   display: "Type 2 diabetes mellitus",
      ...>   active: true
      ...> }

  """

  @type ontology :: :snomed_ct | :icd10 | :rxnorm | :loinc

  @type t :: %__MODULE__{
          code: String.t(),
          system: ontology(),
          display: String.t(),
          fully_specified_name: String.t() | nil,
          synonyms: [String.t()],
          active: boolean(),
          semantic_types: [String.t()],
          properties: map(),
          effective_time: Date.t() | nil
        }

  @enforce_keys [:code, :system, :display]
  defstruct [
    :code,
    :system,
    :display,
    :fully_specified_name,
    :effective_time,
    synonyms: [],
    active: true,
    semantic_types: [],
    properties: %{}
  ]

  @doc """
  Creates a new Concept struct.

  ## Examples

      iex> MedOntology.Concept.new("44054006", :snomed_ct, "Type 2 diabetes mellitus")
      %MedOntology.Concept{
        code: "44054006",
        system: :snomed_ct,
        display: "Type 2 diabetes mellitus",
        active: true,
        synonyms: [],
        semantic_types: [],
        properties: %{}
      }

  """
  @spec new(String.t(), ontology(), String.t(), keyword()) :: t()
  def new(code, system, display, opts \\ []) do
    %__MODULE__{
      code: code,
      system: system,
      display: display,
      fully_specified_name: Keyword.get(opts, :fully_specified_name),
      synonyms: Keyword.get(opts, :synonyms, []),
      active: Keyword.get(opts, :active, true),
      semantic_types: Keyword.get(opts, :semantic_types, []),
      properties: Keyword.get(opts, :properties, %{}),
      effective_time: Keyword.get(opts, :effective_time)
    }
  end
end
