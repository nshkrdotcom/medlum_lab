defmodule ClinicalNerEx.Config do
  @moduledoc """
  Runtime configuration for clinical_ner_ex.

  All configuration can be set in your `config.exs`:

      config :clinical_ner_ex,
        default_method: :hybrid,
        extraction_timeout_ms: 500,
        enable_ontology_linking: true,
        confidence_thresholds: %{
          medication: 0.8,
          lab_value: 0.75,
          diagnosis: 0.7,
          procedure: 0.7,
          temporal: 0.9
        }

  ## Configuration Options

  - `:default_method` - Default extraction method (`:rule_based`, `:transformer`, `:hybrid`)
  - `:entity_methods` - Per-entity-type method overrides
  - `:confidence_thresholds` - Minimum confidence per entity type
  - `:extraction_timeout_ms` - Timeout for extraction operations
  - `:enable_ontology_linking` - Whether to link entities to ontologies
  - `:linker_config` - Configuration for ontology linkers
  """

  @doc """
  Returns the default extraction method.

  ## Examples

      iex> ClinicalNerEx.Config.default_method()
      :hybrid
  """
  @spec default_method() :: :rule_based | :transformer | :hybrid
  def default_method, do: get_env(:default_method, :hybrid)

  @doc """
  Returns per-entity-type method configuration.

  ## Examples

      iex> ClinicalNerEx.Config.entity_methods()
      %{medication: :hybrid, lab_value: :hybrid, diagnosis: :transformer, ...}
  """
  @spec entity_methods() :: map()
  def entity_methods do
    get_env(:entity_methods, %{
      medication: :hybrid,
      lab_value: :hybrid,
      diagnosis: :transformer,
      procedure: :hybrid,
      temporal: :rule_based
    })
  end

  @doc """
  Returns the extraction method for a specific entity type.

  Falls back to `default_method/0` if not configured.

  ## Examples

      iex> ClinicalNerEx.Config.method_for_entity(:medication)
      :hybrid

      iex> ClinicalNerEx.Config.method_for_entity(:temporal)
      :rule_based
  """
  @spec method_for_entity(atom()) :: :rule_based | :transformer | :hybrid
  def method_for_entity(entity_type) do
    entity_methods()
    |> Map.get(entity_type, default_method())
  end

  @doc """
  Returns confidence thresholds per entity type.

  ## Examples

      iex> ClinicalNerEx.Config.confidence_thresholds()
      %{medication: 0.8, lab_value: 0.75, ...}
  """
  @spec confidence_thresholds() :: map()
  def confidence_thresholds do
    get_env(:confidence_thresholds, %{
      medication: 0.8,
      lab_value: 0.75,
      diagnosis: 0.7,
      procedure: 0.7,
      temporal: 0.9
    })
  end

  @doc """
  Returns the confidence threshold for a specific entity type.

  Falls back to 0.7 if not configured.

  ## Examples

      iex> ClinicalNerEx.Config.confidence_threshold_for(:medication)
      0.8
  """
  @spec confidence_threshold_for(atom()) :: float()
  def confidence_threshold_for(entity_type) do
    confidence_thresholds()
    |> Map.get(entity_type, 0.7)
  end

  @doc """
  Returns the extraction timeout in milliseconds.

  ## Examples

      iex> ClinicalNerEx.Config.extraction_timeout_ms()
      500
  """
  @spec extraction_timeout_ms() :: pos_integer()
  def extraction_timeout_ms, do: get_env(:extraction_timeout_ms, 500)

  @doc """
  Returns whether ontology linking is enabled.

  ## Examples

      iex> ClinicalNerEx.Config.enable_ontology_linking?()
      true
  """
  @spec enable_ontology_linking?() :: boolean()
  def enable_ontology_linking?, do: get_env(:enable_ontology_linking, true)

  @doc """
  Returns the linker configuration.

  ## Examples

      iex> ClinicalNerEx.Config.linker_config()
      %{rxnorm: %{enabled: true, max_candidates: 5}, ...}
  """
  @spec linker_config() :: map()
  def linker_config do
    get_env(:linker_config, %{
      rxnorm: %{enabled: true, max_candidates: 5},
      loinc: %{enabled: true, max_candidates: 3},
      snomed: %{enabled: true, max_candidates: 5},
      icd10: %{enabled: true, max_candidates: 3}
    })
  end

  @doc """
  Returns the batch size for parallel extraction.

  ## Examples

      iex> ClinicalNerEx.Config.batch_size()
      32
  """
  @spec batch_size() :: pos_integer()
  def batch_size, do: get_env(:batch_size, 32)

  @doc """
  Returns the maximum number of concurrent extractions.

  ## Examples

      iex> ClinicalNerEx.Config.max_concurrent_extractions()
      4
  """
  @spec max_concurrent_extractions() :: pos_integer()
  def max_concurrent_extractions, do: get_env(:max_concurrent_extractions, 4)

  @doc """
  Returns model configuration.

  ## Examples

      iex> ClinicalNerEx.Config.models()
      %{clinical_bert_ner: %{repo: "...", task: :token_classification}}
  """
  @spec models() :: map()
  def models do
    get_env(:models, %{
      clinical_bert_ner: %{
        repo: "emilyalsentzer/Bio_ClinicalBERT",
        task: :token_classification,
        lazy_load: true
      }
    })
  end

  @doc """
  Returns all configuration as a map.

  ## Examples

      iex> config = ClinicalNerEx.Config.all()
      iex> Map.keys(config)
      [:batch_size, :confidence_thresholds, :default_method, ...]
  """
  @spec all() :: map()
  def all do
    %{
      default_method: default_method(),
      entity_methods: entity_methods(),
      confidence_thresholds: confidence_thresholds(),
      extraction_timeout_ms: extraction_timeout_ms(),
      enable_ontology_linking: enable_ontology_linking?(),
      linker_config: linker_config(),
      batch_size: batch_size(),
      max_concurrent_extractions: max_concurrent_extractions(),
      models: models()
    }
  end

  defp get_env(key, default) do
    Application.get_env(:clinical_ner_ex, key, default)
  end
end
