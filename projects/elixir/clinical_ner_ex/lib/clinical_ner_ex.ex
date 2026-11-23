defmodule ClinicalNerEx do
  @moduledoc """
  Clinical Named Entity Recognition for medical text.

  This library extracts structured medical entities from unstructured clinical text,
  including medications, lab values, diagnoses, procedures, and temporal expressions.

  ## Quick Start

      # Extract all entity types
      {:ok, entities} = ClinicalNerEx.extract("Patient on metformin 500mg BID for diabetes")

      # Extract specific entity types
      {:ok, meds} = ClinicalNerEx.extract_medications("metformin 500mg PO BID")
      {:ok, labs} = ClinicalNerEx.extract_lab_values("A1c 6.5%")

      # With options
      {:ok, entities} = ClinicalNerEx.extract(text,
        method: :hybrid,
        confidence_threshold: 0.8,
        link_ontologies: true
      )

  ## Entity Types

  - `:medication` - Drug names, doses, frequencies, routes
  - `:lab_value` - Lab tests, values, units, reference ranges
  - `:diagnosis` - Conditions, symptoms, findings
  - `:procedure` - Medical procedures, surgeries
  - `:temporal` - Dates, times, durations

  ## Extraction Methods

  - `:rule_based` - Fast regex/pattern matching (< 10ms)
  - `:transformer` - Bumblebee model inference (< 100ms)
  - `:hybrid` - Combined approach (default)

  ## Architecture

  The library uses a pipeline-based architecture:

      Text Input -> Preprocessor -> Coordinator -> Postprocessor -> Linker -> Output

  Key components:
  - **Extractors**: Entity-specific extraction modules
  - **Methods**: Extraction strategies (RuleBased, Transformer, Hybrid)
  - **Pipeline**: Orchestration of extraction process
  - **Linker**: Ontology linking via med_ontology_ex

  ## Integration

  This library integrates with:
  - `med_ontology_ex` for ontology lookups (RxNorm, LOINC, SNOMED-CT, ICD-10)
  - `bumblebee` for transformer-based extraction (optional)
  - CVL agents for hallucination detection in MedlumLlm
  """

  alias ClinicalNerEx.{Config, Entity, Pipeline}

  @type extraction_opts :: [
          method: :rule_based | :transformer | :hybrid,
          entity_types: [Entity.entity_type()],
          confidence_threshold: float(),
          link_ontologies: boolean(),
          timeout_ms: pos_integer()
        ]

  @doc """
  Extract all entity types from clinical text.

  ## Options

  - `:method` - `:rule_based`, `:transformer`, or `:hybrid` (default: `:hybrid`)
  - `:entity_types` - List of types to extract (default: all)
  - `:confidence_threshold` - Minimum confidence (default: 0.7)
  - `:link_ontologies` - Enable ontology linking (default: true)
  - `:timeout_ms` - Extraction timeout (default: 500)

  ## Examples

      iex> {:ok, entities} = ClinicalNerEx.extract("Patient has type 2 diabetes on metformin 500mg BID")
      iex> is_list(entities)
      true

  ## Full Example

      {:ok, entities} = ClinicalNerEx.extract("Patient has type 2 diabetes on metformin 500mg BID")
      # => {:ok, [
      #   %Entity{type: :diagnosis, text: "type 2 diabetes", ...},
      #   %Entity{type: :medication, text: "metformin 500mg BID", ...}
      # ]}
  """
  @spec extract(String.t(), extraction_opts()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract(text, opts \\ []) do
    Pipeline.extract(text, opts)
  end

  @doc """
  Extract medication entities from clinical text.

  Extracts drug names, doses, frequencies, routes, durations, forms, and strengths.

  ## Examples

      iex> {:ok, meds} = ClinicalNerEx.extract_medications("lisinopril 10mg PO daily for HTN")
      iex> is_list(meds)
      true
  """
  @spec extract_medications(String.t(), keyword()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_medications(text, opts \\ []) do
    opts = Keyword.put(opts, :entity_types, [:medication])
    extract(text, opts)
  end

  @doc """
  Extract lab value entities from clinical text.

  Extracts lab names, numeric values, units, and identifies abnormal values.

  ## Examples

      iex> {:ok, labs} = ClinicalNerEx.extract_lab_values("Hemoglobin A1c 8.5% (H), Creatinine 1.1 mg/dL")
      iex> is_list(labs)
      true
  """
  @spec extract_lab_values(String.t(), keyword()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_lab_values(text, opts \\ []) do
    opts = Keyword.put(opts, :entity_types, [:lab_value])
    extract(text, opts)
  end

  @doc """
  Extract diagnosis entities from clinical text.

  Extracts conditions, symptoms, and clinical findings.

  ## Examples

      iex> {:ok, diagnoses} = ClinicalNerEx.extract_diagnoses("Acute exacerbation of COPD with hypoxia")
      iex> is_list(diagnoses)
      true
  """
  @spec extract_diagnoses(String.t(), keyword()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_diagnoses(text, opts \\ []) do
    opts = Keyword.put(opts, :entity_types, [:diagnosis])
    extract(text, opts)
  end

  @doc """
  Extract procedure entities from clinical text.

  Extracts medical procedures, surgeries, and interventions.

  ## Examples

      iex> {:ok, procedures} = ClinicalNerEx.extract_procedures("s/p CABG x3 in 2024, colonoscopy planned")
      iex> is_list(procedures)
      true
  """
  @spec extract_procedures(String.t(), keyword()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_procedures(text, opts \\ []) do
    opts = Keyword.put(opts, :entity_types, [:procedure])
    extract(text, opts)
  end

  @doc """
  Extract temporal expressions from clinical text.

  Extracts dates, times, durations, and temporal relationships.

  ## Examples

      iex> {:ok, temporal} = ClinicalNerEx.extract_temporal("Started on 1/15/2026, continue for 2 weeks")
      iex> is_list(temporal)
      true
  """
  @spec extract_temporal(String.t(), keyword()) :: {:ok, [Entity.t()]} | {:error, term()}
  def extract_temporal(text, opts \\ []) do
    opts = Keyword.put(opts, :entity_types, [:temporal])
    extract(text, opts)
  end

  @doc """
  Extract entities from multiple texts in parallel.

  ## Examples

      iex> texts = ["Patient on metformin 500mg", "Labs show A1c 6.5%", "History of COPD"]
      iex> {:ok, results} = ClinicalNerEx.extract_batch(texts)
      iex> length(results)
      3
  """
  @spec extract_batch([String.t()], keyword()) :: {:ok, [[Entity.t()]]} | {:error, term()}
  def extract_batch(texts, opts \\ []) do
    Pipeline.extract_batch(texts, opts)
  end

  @doc """
  Stream extraction for large document sets.

  Returns a stream that yields extraction results.

  ## Examples

      iex> texts = ["Patient on aspirin", "Labs: A1c 6.5%"]
      iex> stream = ClinicalNerEx.extract_stream(texts)
      iex> Enum.count(stream)
      2
  """
  @spec extract_stream(Enumerable.t(), keyword()) :: Enumerable.t()
  def extract_stream(texts, opts \\ []) do
    Pipeline.extract_stream(texts, opts)
  end

  @doc """
  Get the current extraction configuration.

  ## Examples

      iex> config = ClinicalNerEx.config()
      iex> Map.has_key?(config, :default_method)
      true
  """
  @spec config() :: map()
  def config do
    %{
      default_method: Config.default_method(),
      confidence_thresholds: Config.confidence_thresholds(),
      extraction_timeout_ms: Config.extraction_timeout_ms(),
      enable_ontology_linking: Config.enable_ontology_linking?()
    }
  end

  @doc """
  Returns the library version.

  ## Examples

      iex> ClinicalNerEx.version()
      "0.1.0"
  """
  @spec version() :: String.t()
  def version do
    "0.1.0"
  end
end
