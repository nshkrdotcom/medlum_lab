defmodule MedOntology.Ontology do
  @moduledoc """
  Behaviour for ontology-specific modules.

  Each supported ontology (SNOMED-CT, ICD-10, RxNorm, LOINC) must implement
  this behaviour to provide consistent operations across different terminologies.

  ## Implementing an Ontology Module

      defmodule MedOntology.MyOntology do
        @behaviour MedOntology.Ontology

        alias MedOntology.Concept

        @impl true
        def lookup(code, opts \\\\ []) do
          # Look up concept by code
          {:ok, %Concept{code: code, system: :my_ontology, display: "..."}}
        end

        @impl true
        def search(query, opts \\\\ []) do
          # Search for concepts
          {:ok, [%Concept{...}]}
        end

        @impl true
        def valid?(code) do
          # Validate code format and existence
          true
        end

        @impl true
        def ancestors(code, opts \\\\ []) do
          # Get parent concepts
          {:ok, [%Concept{...}]}
        end

        @impl true
        def descendants(code, opts \\\\ []) do
          # Get child concepts
          {:ok, [%Concept{...}]}
        end
      end

  """

  alias MedOntology.{Concept, SearchResult}

  @doc """
  Looks up a concept by its code.

  ## Options

    * `:include_relationships` - Include related concepts (default: false)
    * `:include_mappings` - Include cross-ontology mappings (default: false)

  ## Examples

      iex> MedOntology.SnomedCT.lookup("44054006")
      {:ok, %Concept{code: "44054006", display: "Type 2 diabetes mellitus"}}

      iex> MedOntology.SnomedCT.lookup("invalid")
      {:error, :not_found}

  """
  @callback lookup(code :: String.t(), opts :: keyword()) ::
              {:ok, Concept.t()} | {:error, :not_found | term()}

  @doc """
  Searches for concepts matching the given query text.

  ## Options

    * `:limit` - Maximum number of results (default: 25)
    * `:semantic_types` - Filter by semantic types (default: [])
    * `:active_only` - Only return active concepts (default: true)
    * `:min_score` - Minimum relevance score (default: 0.5)

  ## Examples

      iex> MedOntology.SnomedCT.search("diabetes")
      {:ok, [%SearchResult{concept: %Concept{...}, score: 0.95}]}

  """
  @callback search(query :: String.t(), opts :: keyword()) ::
              {:ok, [SearchResult.t()]} | {:error, term()}

  @doc """
  Validates whether a code is valid for this ontology.

  This performs both syntactic validation (format check) and
  semantic validation (existence check).

  ## Examples

      iex> MedOntology.ICD10.valid?("E11.9")
      true

      iex> MedOntology.ICD10.valid?("ZZZ.99")
      false

  """
  @callback valid?(code :: String.t()) :: boolean()

  @doc """
  Gets the ancestor (parent) concepts for a given code.

  Returns concepts in order from immediate parent to root.

  ## Options

    * `:max_depth` - Maximum levels to traverse (default: unlimited)

  ## Examples

      iex> MedOntology.SnomedCT.ancestors("44054006")
      {:ok, [%Concept{code: "73211009", display: "Diabetes mellitus"}]}

  """
  @callback ancestors(code :: String.t(), opts :: keyword()) ::
              {:ok, [Concept.t()]} | {:error, term()}

  @doc """
  Gets the descendant (child) concepts for a given code.

  ## Options

    * `:max_depth` - Maximum levels to traverse (default: 1)
    * `:limit` - Maximum number of results (default: 100)

  ## Examples

      iex> MedOntology.SnomedCT.descendants("73211009", max_depth: 1)
      {:ok, [%Concept{code: "44054006", display: "Type 2 diabetes mellitus"}]}

  """
  @callback descendants(code :: String.t(), opts :: keyword()) ::
              {:ok, [Concept.t()]} | {:error, term()}
end
