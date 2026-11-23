defmodule MedOntology.Config do
  @moduledoc """
  Runtime configuration for med_ontology_ex.

  This module provides access to configuration values for the library.
  Configuration can be set in your `config.exs` files:

      config :med_ontology_ex,
        umls_api_key: System.get_env("UMLS_API_KEY"),
        cache_dir: "/var/lib/med_ontology/cache",
        cache_warmup_on_start: true,
        sync_enabled: false

  ## API Credentials

    * `umls_api_key` - API key for UMLS Terminology Services
    * `loinc_username` - Username for LOINC FHIR API
    * `loinc_password` - Password for LOINC FHIR API
    * `who_client_id` - OAuth2 client ID for WHO ICD API
    * `who_client_secret` - OAuth2 client secret for WHO ICD API

  ## Cache Settings

    * `cache_dir` - Directory for DETS cache files (default: "/var/lib/med_ontology/cache")
    * `cache_warmup_on_start` - Whether to load cache on startup (default: true)

  ## Sync Settings

    * `sync_enabled` - Enable background sync (default: false)
    * `sync_interval_hours` - Hours between sync runs (default: 24)

  ## Performance Settings

    * `http_timeout_ms` - HTTP request timeout in milliseconds (default: 5000)
    * `search_result_limit` - Default limit for search results (default: 25)

  """

  @doc """
  Returns the UMLS API key.
  """
  @spec umls_api_key() :: String.t() | nil
  def umls_api_key, do: get_env(:umls_api_key)

  @doc """
  Returns the LOINC username.
  """
  @spec loinc_username() :: String.t() | nil
  def loinc_username, do: get_env(:loinc_username)

  @doc """
  Returns the LOINC password.
  """
  @spec loinc_password() :: String.t() | nil
  def loinc_password, do: get_env(:loinc_password)

  @doc """
  Returns the WHO ICD API client ID.
  """
  @spec who_client_id() :: String.t() | nil
  def who_client_id, do: get_env(:who_client_id)

  @doc """
  Returns the WHO ICD API client secret.
  """
  @spec who_client_secret() :: String.t() | nil
  def who_client_secret, do: get_env(:who_client_secret)

  @doc """
  Returns the cache directory path.
  """
  @spec cache_dir() :: String.t()
  def cache_dir, do: get_env(:cache_dir, default_cache_dir())

  @doc """
  Returns whether to warm up cache on application start.
  """
  @spec cache_warmup_on_start?() :: boolean()
  def cache_warmup_on_start?, do: get_env(:cache_warmup_on_start, true)

  @doc """
  Returns whether background sync is enabled.
  """
  @spec sync_enabled?() :: boolean()
  def sync_enabled?, do: get_env(:sync_enabled, false)

  @doc """
  Returns the sync interval in hours.
  """
  @spec sync_interval_hours() :: pos_integer()
  def sync_interval_hours, do: get_env(:sync_interval_hours, 24)

  @doc """
  Returns the HTTP timeout in milliseconds.
  """
  @spec http_timeout_ms() :: pos_integer()
  def http_timeout_ms, do: get_env(:http_timeout_ms, 5_000)

  @doc """
  Returns the default search result limit.
  """
  @spec search_result_limit() :: pos_integer()
  def search_result_limit, do: get_env(:search_result_limit, 25)

  @doc """
  Returns the list of enabled ontologies.
  """
  @spec enabled_ontologies() :: [atom()]
  def enabled_ontologies, do: get_env(:enabled_ontologies, [:snomed_ct, :icd10, :rxnorm, :loinc])

  @doc """
  Returns the maximum number of retries for API requests.
  """
  @spec max_retries() :: non_neg_integer()
  def max_retries, do: get_env(:max_retries, 3)

  @doc """
  Returns the retry delay in milliseconds.
  """
  @spec retry_delay_ms() :: pos_integer()
  def retry_delay_ms, do: get_env(:retry_delay_ms, 1_000)

  # Private helpers

  defp get_env(key, default \\ nil) do
    Application.get_env(:med_ontology_ex, key, default)
  end

  defp default_cache_dir do
    case :os.type() do
      {:unix, _} -> "/var/lib/med_ontology/cache"
      {:win32, _} -> Path.join(System.tmp_dir!(), "med_ontology/cache")
    end
  end
end
