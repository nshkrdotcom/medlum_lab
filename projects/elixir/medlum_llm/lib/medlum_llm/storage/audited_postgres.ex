defmodule MedlumLlm.Storage.AuditedPostgres do
  @moduledoc """
  HIPAA-compliant audited storage wrapper for Forge.Storage.Postgres.

  This module wraps `Forge.Storage.Postgres` to add audit logging for all
  storage operations. Audit logs contain hashes and metadata only - never
  Protected Health Information (PHI).

  ## Audit Trail

  All operations are logged via Telemetry events:
  - `[:medlum_llm, :storage, :audit]` - Emitted for each operation

  ## Audit Log Schema

  Each audit entry contains:
  - `timestamp` - When the operation occurred
  - `operation` - Type of operation (`:put_sample`, `:get_sample`, etc.)
  - `sample_id_hash` - SHA256 hash of sample ID (first 16 chars)
  - `pipeline_name` - Name of the pipeline
  - `user_id` - Optional user ID if available

  ## Configuration

  - `:pipeline_name` - Required. Name of the pipeline for audit context
  - `:pipeline_manifest` - Optional. Pipeline manifest for versioning
  - `:audit_enabled` - Optional. Enable/disable auditing (default: `true`)

  ## Example

      iex> {:ok, state} = AuditedPostgres.init(pipeline_name: :cvl_training)
      iex> {:ok, state} = AuditedPostgres.store([sample], state)
      # Audit log emitted via Telemetry
  """

  @behaviour Forge.Storage

  require Logger

  alias Forge.Storage.Postgres

  @type state :: %{
          postgres_state: Postgres.t(),
          pipeline_name: atom(),
          audit_enabled: boolean()
        }

  @impl true
  @spec init(keyword()) :: {:ok, state()}
  def init(opts) do
    pipeline_name = Keyword.fetch!(opts, :pipeline_name)
    audit_enabled = Keyword.get(opts, :audit_enabled, true)

    # Initialize underlying Postgres storage
    postgres_opts =
      opts
      |> Keyword.put(:pipeline_name, pipeline_name)

    case Postgres.init(postgres_opts) do
      {:ok, postgres_state} ->
        state = %{
          postgres_state: postgres_state,
          pipeline_name: pipeline_name,
          audit_enabled: audit_enabled
        }

        log_audit(:init, nil, state, %{})
        {:ok, state}

      error ->
        error
    end
  end

  @impl true
  @spec store([Forge.Sample.t()], state()) :: {:ok, state()} | {:error, term()}
  def store(samples, state) do
    # Log audit for each sample (without PHI)
    if state.audit_enabled do
      Enum.each(samples, fn sample ->
        log_audit(:put_sample, sample.id, state, %{
          status: sample.status,
          has_measurements: map_size(sample.measurements || %{}) > 0
        })
      end)
    end

    case Postgres.store(samples, state.postgres_state) do
      {:ok, new_postgres_state} ->
        {:ok, %{state | postgres_state: new_postgres_state}}

      error ->
        error
    end
  end

  @impl true
  @spec retrieve(String.t(), state()) :: {:ok, Forge.Sample.t(), state()} | {:error, :not_found}
  def retrieve(sample_id, state) do
    log_audit(:get_sample, sample_id, state, %{})

    case Postgres.retrieve(sample_id, state.postgres_state) do
      {:ok, sample, new_postgres_state} ->
        {:ok, sample, %{state | postgres_state: new_postgres_state}}

      error ->
        error
    end
  end

  @impl true
  @spec list([{atom(), term()}], state()) :: {:ok, [Forge.Sample.t()], state()}
  def list(filters, state) do
    log_audit(:list_samples, nil, state, %{filters: sanitize_filters(filters)})

    case Postgres.list(filters, state.postgres_state) do
      {:ok, samples, new_postgres_state} ->
        {:ok, samples, %{state | postgres_state: new_postgres_state}}

      error ->
        error
    end
  end

  @impl true
  @spec cleanup(state()) :: :ok
  def cleanup(state) do
    log_audit(:cleanup, nil, state, %{})
    Postgres.cleanup(state.postgres_state)
  end

  # Additional audit-specific functions

  @doc """
  Store a single sample with audit logging.
  """
  @spec put_sample(state(), Forge.Sample.t()) :: {:ok, state()} | {:error, term()}
  def put_sample(state, sample) do
    store([sample], state)
  end

  @doc """
  Get a single sample by ID with audit logging.
  """
  @spec get_sample(state(), String.t()) :: {:ok, Forge.Sample.t(), state()} | {:error, :not_found}
  def get_sample(state, sample_id) do
    retrieve(sample_id, state)
  end

  @doc """
  Store a measurement result with audit logging.
  """
  @spec put_measurement(state(), map()) :: {:ok, state()} | {:error, term()}
  def put_measurement(state, measurement) do
    log_audit(:put_measurement, measurement[:sample_id], state, %{
      measurement_key: measurement[:key],
      measurement_version: measurement[:version]
    })

    # TODO: Call Postgres.put_measurement/2 once Forge.Storage.Postgres implements it
    if function_exported?(Postgres, :put_measurement, 2) do
      case apply(Postgres, :put_measurement, [state.postgres_state, measurement]) do
        {:ok, new_postgres_state} ->
          {:ok, %{state | postgres_state: new_postgres_state}}

        error ->
          error
      end
    else
      Logger.warning("Forge.Storage.Postgres.put_measurement/2 not yet implemented")
      {:error, :not_implemented}
    end
  end

  @doc """
  List measurements with audit logging.
  """
  @spec list_measurements(state(), [{atom(), term()}]) :: {:ok, [map()], state()}
  def list_measurements(state, filters) do
    log_audit(:list_measurements, nil, state, %{filters: sanitize_filters(filters)})

    # TODO: Call Postgres.list_measurements/2 once Forge.Storage.Postgres implements it
    if function_exported?(Postgres, :list_measurements, 2) do
      case apply(Postgres, :list_measurements, [state.postgres_state, filters]) do
        {:ok, measurements, new_postgres_state} ->
          {:ok, measurements, %{state | postgres_state: new_postgres_state}}

        error ->
          error
      end
    else
      Logger.warning("Forge.Storage.Postgres.list_measurements/2 not yet implemented")
      {:error, :not_implemented}
    end
  end

  @doc """
  Get audit statistics for this pipeline.
  """
  @spec audit_stats(state()) :: map()
  def audit_stats(state) do
    %{
      pipeline_name: state.pipeline_name,
      audit_enabled: state.audit_enabled,
      # In production, this would query an audit_logs table
      operations_logged: :telemetry_recorded
    }
  end

  # Private functions

  @spec log_audit(atom(), String.t() | nil, state(), map()) :: :ok
  defp log_audit(operation, sample_id, state, metadata) do
    if state.audit_enabled do
      entry = %{
        timestamp: DateTime.utc_now(),
        operation: operation,
        sample_id_hash: hash_id(sample_id),
        pipeline_name: state.pipeline_name,
        metadata: metadata
      }

      :telemetry.execute(
        [:medlum_llm, :storage, :audit],
        %{count: 1},
        entry
      )

      Logger.debug(
        "[Audit] #{operation} on pipeline #{state.pipeline_name}" <>
          if(sample_id, do: " for sample #{hash_id(sample_id)}", else: "")
      )
    end

    :ok
  end

  @spec hash_id(String.t() | nil) :: String.t() | nil
  defp hash_id(nil), do: nil

  defp hash_id(id) do
    :crypto.hash(:sha256, to_string(id))
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  @spec sanitize_filters([{atom(), term()}]) :: [{atom(), term()}]
  defp sanitize_filters(filters) do
    # Remove any potentially sensitive filter values
    Enum.map(filters, fn
      {:status, value} -> {:status, value}
      {:after, _} -> {:after, :redacted}
      {:before, _} -> {:before, :redacted}
      {key, _value} -> {key, :present}
    end)
  end
end
