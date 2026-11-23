defmodule MedOntology.SearchResult do
  @moduledoc """
  Represents a search result with relevance score.

  When searching for concepts by text, results are returned with a relevance
  score indicating how well the concept matches the search query.

  ## Fields

    * `:concept` - The matched concept
    * `:score` - Relevance score (0.0 to 1.0, higher is better)
    * `:matched_term` - The specific term that matched the query

  ## Examples

      iex> %MedOntology.SearchResult{
      ...>   concept: %MedOntology.Concept{code: "44054006", system: :snomed_ct, display: "Type 2 diabetes mellitus"},
      ...>   score: 0.95,
      ...>   matched_term: "Type 2 diabetes mellitus"
      ...> }

  """

  alias MedOntology.Concept

  @type t :: %__MODULE__{
          concept: Concept.t(),
          score: float(),
          matched_term: String.t()
        }

  @enforce_keys [:concept, :score, :matched_term]
  defstruct [:concept, :score, :matched_term]

  @doc """
  Creates a new SearchResult struct.

  ## Examples

      iex> concept = MedOntology.Concept.new("44054006", :snomed_ct, "Type 2 diabetes mellitus")
      iex> MedOntology.SearchResult.new(concept, 0.95, "Type 2 diabetes mellitus")
      %MedOntology.SearchResult{
        concept: %MedOntology.Concept{code: "44054006", system: :snomed_ct, display: "Type 2 diabetes mellitus"},
        score: 0.95,
        matched_term: "Type 2 diabetes mellitus"
      }

  """
  @spec new(Concept.t(), float(), String.t()) :: t()
  def new(concept, score, matched_term) do
    %__MODULE__{
      concept: concept,
      score: score,
      matched_term: matched_term
    }
  end
end
