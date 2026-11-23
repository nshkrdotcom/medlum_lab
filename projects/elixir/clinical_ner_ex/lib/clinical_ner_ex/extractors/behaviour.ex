defmodule ClinicalNerEx.Extractors.Behaviour do
  @moduledoc """
  Behaviour for entity extractors.

  All entity extractors must implement this behaviour to be used
  in the extraction pipeline.

  ## Implementing an Extractor

  To create a new extractor, implement the three required callbacks:

      defmodule ClinicalNerEx.Extractors.Medication do
        @behaviour ClinicalNerEx.Extractors.Behaviour

        @impl true
        def entity_type, do: :medication

        @impl true
        def supported_methods, do: [:rule_based, :transformer, :hybrid]

        @impl true
        def extract(context) do
          # Extract medication entities from context
          {:ok, entities}
        end
      end

  ## Context Structure

  The extraction context contains:

  - `text` - The original text to extract from
  - `tokens` - Tokenized text (may be nil)
  - `sentences` - Sentence-segmented text (may be nil)
  - `method` - The extraction method to use
  - `opts` - Additional options

  ## Examples

      context = %{
        text: "Patient on metformin 500mg BID",
        tokens: ["Patient", "on", "metformin", "500mg", "BID"],
        sentences: ["Patient on metformin 500mg BID"],
        method: :rule_based,
        opts: [confidence_threshold: 0.8]
      }

      {:ok, entities} = MyExtractor.extract(context)
  """

  alias ClinicalNerEx.Entity

  @type context :: %{
          text: String.t(),
          tokens: [String.t()] | nil,
          sentences: [String.t()] | nil,
          method: atom(),
          opts: keyword()
        }

  @doc """
  Extract entities of this type from the context.

  Returns `{:ok, entities}` on success or `{:error, reason}` on failure.
  """
  @callback extract(context()) :: {:ok, [Entity.t()]} | {:error, term()}

  @doc """
  Return the entity type this extractor handles.

  Must return one of the valid entity types:
  `:medication`, `:lab_value`, `:diagnosis`, `:procedure`, `:temporal`, `:finding`
  """
  @callback entity_type() :: Entity.entity_type()

  @doc """
  Return the extraction methods supported by this extractor.

  Valid methods are:
  - `:rule_based` - Fast regex/pattern matching
  - `:transformer` - ML model inference
  - `:hybrid` - Combined approach
  """
  @callback supported_methods() :: [:rule_based | :transformer | :hybrid]

  @doc """
  Checks if a module implements the Extractor behaviour.

  ## Examples

      iex> ClinicalNerEx.Extractors.Behaviour.extractor?(ClinicalNerEx.Extractors.Medication)
      true

      iex> ClinicalNerEx.Extractors.Behaviour.extractor?(String)
      false
  """
  @spec extractor?(module()) :: boolean()
  def extractor?(module) when is_atom(module) do
    behaviours = module.module_info(:attributes)[:behaviour] || []
    __MODULE__ in behaviours
  rescue
    UndefinedFunctionError -> false
  end
end
