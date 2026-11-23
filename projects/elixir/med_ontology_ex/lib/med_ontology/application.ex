defmodule MedOntology.Application do
  @moduledoc """
  OTP Application for med_ontology_ex.

  Starts the supervision tree including:

    * `MedOntology.Cache.Server` - GenServer for cache management
    * `Finch` - HTTP connection pools for external APIs
    * `MedOntology.Cache.Sync` - Background sync process (optional)

  ## Supervision Tree

  ```
  MedOntology.Supervisor
  +-- MedOntology.Cache.Server     (GenServer)
  +-- Finch (HTTP connection pool)  (Supervisor)
  +-- MedOntology.Cache.Sync       (GenServer, optional)
  ```

  ## Configuration

  The application can be configured through `config.exs`:

      config :med_ontology_ex,
        cache_dir: "/var/lib/med_ontology/cache",
        cache_warmup_on_start: true,
        sync_enabled: false,
        sync_interval_hours: 24

  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = build_children()

    # Attach telemetry handlers
    MedOntology.Telemetry.setup()

    opts = [strategy: :one_for_one, name: MedOntology.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("MedOntology application started")
        {:ok, pid}

      error ->
        error
    end
  end

  defp build_children do
    base_children = [
      # Cache management
      {MedOntology.Cache.Server, cache_server_opts()},

      # HTTP connection pools
      {Finch, name: MedOntology.Finch, pools: pool_config()}
    ]

    # Add sync process if enabled
    if sync_enabled?() do
      base_children ++ [{MedOntology.Cache.Sync, sync_opts()}]
    else
      base_children
    end
  end

  defp cache_server_opts do
    [
      cache_dir: MedOntology.Config.cache_dir(),
      warmup_on_start: MedOntology.Config.cache_warmup_on_start?()
    ]
  end

  defp sync_opts do
    [
      enabled: sync_enabled?(),
      interval: hours_to_ms(MedOntology.Config.sync_interval_hours())
    ]
  end

  defp sync_enabled? do
    MedOntology.Config.sync_enabled?()
  end

  defp pool_config do
    %{
      # UMLS Terminology Services
      :default => [size: 10, count: 1],
      # RxNav API
      "https://rxnav.nlm.nih.gov" => [size: 10, count: 1],
      # LOINC FHIR server
      "https://fhir.loinc.org" => [size: 5, count: 1],
      # WHO ICD API
      "https://id.who.int" => [size: 5, count: 1],
      # SNOMED Snowstorm
      "https://browser.ihtsdotools.org" => [size: 10, count: 1]
    }
  end

  defp hours_to_ms(hours), do: hours * 60 * 60 * 1000
end
