defmodule MedOntology.Relationship do
  @moduledoc """
  Represents a relationship between concepts in a medical ontology.

  Relationships define how concepts are connected to each other, such as
  hierarchical (is-a) relationships or attribute relationships like
  finding_site or has_ingredient.

  ## Fields

    * `:source_code` - The code of the source concept
    * `:target_code` - The code of the target concept
    * `:type` - The type of relationship
    * `:active` - Whether the relationship is currently active
    * `:group` - Role group number for SNOMED-CT (optional)

  ## Relationship Types

  Common relationship types include:

    * `:is_a` - Hierarchical subtype relationship (SNOMED-CT, ICD-10)
    * `:part_of` - Part-whole relationship
    * `:has_ingredient` - Drug ingredient relationship (RxNorm)
    * `:finding_site` - Anatomical location of finding (SNOMED-CT)
    * `:associated_morphology` - Morphological abnormality (SNOMED-CT)
    * `:causative_agent` - Cause of condition (SNOMED-CT)
    * `:parent_category` - Parent category (ICD-10)

  ## Examples

      iex> %MedOntology.Relationship{
      ...>   source_code: "44054006",
      ...>   target_code: "73211009",
      ...>   type: :is_a,
      ...>   active: true
      ...> }

  """

  @type relationship_type ::
          :is_a
          | :part_of
          | :has_ingredient
          | :finding_site
          | :associated_morphology
          | :causative_agent
          | :parent_category
          | :has_dose_form
          | :tradename_of
          | :component
          | :property
          | :time_aspect
          | :scale_type
          | :method_type

  @type t :: %__MODULE__{
          source_code: String.t(),
          target_code: String.t(),
          type: relationship_type(),
          active: boolean(),
          group: integer() | nil
        }

  @enforce_keys [:source_code, :target_code, :type]
  defstruct [:source_code, :target_code, :type, :group, active: true]

  @doc """
  Creates a new Relationship struct.

  ## Examples

      iex> MedOntology.Relationship.new("44054006", "73211009", :is_a)
      %MedOntology.Relationship{
        source_code: "44054006",
        target_code: "73211009",
        type: :is_a,
        active: true
      }

  """
  @spec new(String.t(), String.t(), relationship_type(), keyword()) :: t()
  def new(source_code, target_code, type, opts \\ []) do
    %__MODULE__{
      source_code: source_code,
      target_code: target_code,
      type: type,
      active: Keyword.get(opts, :active, true),
      group: Keyword.get(opts, :group)
    }
  end
end
