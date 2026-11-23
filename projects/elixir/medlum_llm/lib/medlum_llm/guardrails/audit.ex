defmodule MedlumLlm.Guardrails.Audit do
  @moduledoc """
  HIPAA-compliant audit logging for guardrail operations.

  Provides audit trail functionality for redaction and validation operations
  without storing or logging Protected Health Information (PHI).

  ## Features

  - Hash-based input/output tracking (no PHI in logs)
  - Redaction type and count tracking
  - Telemetry event emission
  - Operator and session tracking

  ## Compliance

  Designed for HIPAA audit requirements:
  - Logs operations without content
  - Tracks who performed operations
  - Records timestamps
  - Supports retention policies

  ## Usage

      # Log a redaction operation
      MedlumLlm.Guardrails.Audit.log_redaction(manifest, "user_123", "session_abc")

      # Subscribe to telemetry events
      :telemetry.attach(
        "audit-handler",
        [:medlum_llm, :guardrails, :redaction],
        &handle_audit/4,
        nil
      )
  """

  require Logger

  @type audit_entry :: %{
          timestamp: DateTime.t(),
          operation: atom(),
          input_hash: String.t() | nil,
          output_hash: String.t() | nil,
          redaction_types: [atom()],
          redaction_count: non_neg_integer(),
          operator_id: String.t() | nil,
          session_id: String.t() | nil,
          metadata: map()
        }

  @doc """
  Logs a redaction operation without exposing PHI.

  Uses the manifest from `Redactor.redact_with_manifest/2` to record
  what types of PHI were redacted and how many, without storing the actual values.

  ## Parameters

  - `manifest` - Redaction manifest from `Redactor.redact_with_manifest/2`
  - `operator_id` - Optional identifier for the user/system performing the operation
  - `session_id` - Optional session identifier

  ## Returns

  `{:ok, audit_entry}` with the logged entry

  ## Examples

      {redacted, manifest} = Redactor.redact_with_manifest(text)
      {:ok, entry} = Audit.log_redaction(manifest, "user_123", "session_abc")
  """
  @spec log_redaction(map(), String.t() | nil, String.t() | nil) :: {:ok, audit_entry()}
  def log_redaction(manifest, operator_id \\ nil, session_id \\ nil) do
    entry = %{
      timestamp: DateTime.utc_now(),
      operation: :redact,
      input_hash: Map.get(manifest, :original_hash),
      output_hash: Map.get(manifest, :redacted_hash),
      redaction_types: Map.keys(Map.get(manifest, :redaction_types, %{})),
      redaction_count: Map.get(manifest, :redaction_count, 0),
      operator_id: operator_id,
      session_id: session_id,
      metadata: %{
        mode: Map.get(manifest, :mode),
        type_counts: Map.get(manifest, :redaction_types, %{})
      }
    }

    # Emit telemetry event
    :telemetry.execute(
      [:medlum_llm, :guardrails, :redaction],
      %{count: entry.redaction_count},
      Map.take(entry, [:operation, :redaction_types, :operator_id, :session_id])
    )

    # Log at info level (no PHI)
    Logger.info(
      "[Guardrails.Audit] Redaction: #{entry.redaction_count} items, types=#{inspect(entry.redaction_types)}"
    )

    {:ok, entry}
  end

  @doc """
  Logs a validation operation.

  Records that validation was performed, whether PHI was detected,
  and what types were found.

  ## Parameters

  - `result` - Detection result from `ClinicalPII.detect/2`
  - `operation` - Operation type (`:validate_input` or `:validate_output`)
  - `operator_id` - Optional operator identifier
  - `session_id` - Optional session identifier
  - `input_hash` - Optional hash of input (for correlation)

  ## Examples

      result = ClinicalPII.detect(text)
      {:ok, entry} = Audit.log_validation(result, :validate_input, "user_123")
  """
  @spec log_validation(
          {:safe, map()} | {:detected, map()},
          atom(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil
        ) :: {:ok, audit_entry()}
  def log_validation(
        detection_result,
        operation,
        operator_id \\ nil,
        session_id \\ nil,
        input_hash \\ nil
      ) do
    {outcome, detected_types, detection_count} =
      case detection_result do
        {:safe, _} ->
          {:safe, [], 0}

        {:detected, result} ->
          types = Map.get(result, :patterns_matched, [])
          count = get_in(result, [:metadata, :detection_count]) || length(types)
          {:detected, types, count}
      end

    entry = %{
      timestamp: DateTime.utc_now(),
      operation: operation,
      input_hash: input_hash,
      output_hash: nil,
      redaction_types: detected_types,
      redaction_count: detection_count,
      operator_id: operator_id,
      session_id: session_id,
      metadata: %{
        outcome: outcome
      }
    }

    # Emit telemetry event
    :telemetry.execute(
      [:medlum_llm, :guardrails, :validation],
      %{count: detection_count},
      %{
        operation: operation,
        outcome: outcome,
        detected_types: detected_types,
        operator_id: operator_id,
        session_id: session_id
      }
    )

    # Log appropriately based on outcome
    log_msg =
      "[Guardrails.Audit] Validation (#{operation}): outcome=#{outcome}, detected_types=#{inspect(detected_types)}"

    case outcome do
      :safe -> Logger.debug(log_msg)
      :detected -> Logger.info(log_msg)
    end

    {:ok, entry}
  end

  @doc """
  Logs an error during guardrail processing.

  Records errors without exposing input content.

  ## Parameters

  - `operation` - Operation that failed
  - `error` - Error term
  - `operator_id` - Optional operator identifier
  - `session_id` - Optional session identifier

  ## Examples

      Audit.log_error(:redact, :pattern_timeout, "user_123", "session_abc")
  """
  @spec log_error(atom(), term(), String.t() | nil, String.t() | nil) :: {:ok, audit_entry()}
  def log_error(operation, error, operator_id \\ nil, session_id \\ nil) do
    entry = %{
      timestamp: DateTime.utc_now(),
      operation: operation,
      input_hash: nil,
      output_hash: nil,
      redaction_types: [],
      redaction_count: 0,
      operator_id: operator_id,
      session_id: session_id,
      metadata: %{
        outcome: :error,
        error: sanitize_error(error)
      }
    }

    # Emit telemetry
    :telemetry.execute(
      [:medlum_llm, :guardrails, :error],
      %{count: 1},
      %{
        operation: operation,
        error_type: error_type(error),
        operator_id: operator_id,
        session_id: session_id
      }
    )

    Logger.warning(
      "[Guardrails.Audit] Error in #{operation}: #{sanitize_error(error)}"
    )

    {:ok, entry}
  end

  @doc """
  Returns telemetry event names for attachment.

  Use with `:telemetry.attach/4` to subscribe to audit events.

  ## Examples

      events = MedlumLlm.Guardrails.Audit.telemetry_events()
      :telemetry.attach_many("my-handler", events, &handle/4, nil)
  """
  @spec telemetry_events() :: [list()]
  def telemetry_events do
    [
      [:medlum_llm, :guardrails, :redaction],
      [:medlum_llm, :guardrails, :validation],
      [:medlum_llm, :guardrails, :error]
    ]
  end

  @doc """
  Generates a hash for input text (for audit correlation).

  Does not store the text, only returns a hash for logging.

  ## Examples

      hash = Audit.hash_input("some text")
      # => "abc123..."
  """
  @spec hash_input(String.t()) :: String.t()
  def hash_input(text) when is_binary(text) do
    :crypto.hash(:sha256, text)
    |> Base.encode16(case: :lower)
  end

  # Private functions

  defp sanitize_error(error) when is_binary(error), do: String.slice(error, 0, 200)
  defp sanitize_error(error) when is_atom(error), do: Atom.to_string(error)

  defp sanitize_error(%{message: msg}) when is_binary(msg), do: String.slice(msg, 0, 200)

  defp sanitize_error(error) do
    # Convert to string but truncate to avoid logging sensitive data
    error
    |> inspect(limit: 100)
    |> String.slice(0, 200)
  end

  defp error_type(error) when is_atom(error), do: error
  defp error_type(%{__struct__: struct}), do: struct
  defp error_type(_), do: :unknown
end
