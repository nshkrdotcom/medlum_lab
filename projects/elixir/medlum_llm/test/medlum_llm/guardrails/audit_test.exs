defmodule MedlumLlm.Guardrails.AuditTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Guardrails.Audit
  alias MedlumLlm.Guardrails.Redactor

  describe "log_redaction/3" do
    test "logs redaction operation and returns entry" do
      text = "MRN: 12345678, DOB: 01/15/1980"
      {_redacted, manifest} = Redactor.redact_with_manifest(text)

      {:ok, entry} = Audit.log_redaction(manifest, "user_123", "session_abc")

      assert entry.operation == :redact
      assert entry.operator_id == "user_123"
      assert entry.session_id == "session_abc"
    end

    test "entry contains redaction types without PHI values" do
      text = "MRN: 12345678, DOB: 01/15/1980"
      {_redacted, manifest} = Redactor.redact_with_manifest(text)

      {:ok, entry} = Audit.log_redaction(manifest)

      assert :mrn in entry.redaction_types
      assert :dob in entry.redaction_types
      assert entry.redaction_count == 2
    end

    test "entry contains hashes, not content" do
      text = "MRN: 12345678"
      {_redacted, manifest} = Redactor.redact_with_manifest(text)

      {:ok, entry} = Audit.log_redaction(manifest)

      assert is_binary(entry.input_hash)
      assert is_binary(entry.output_hash)
      # Hashes should be SHA256 hex (64 chars)
      assert String.length(entry.input_hash) == 64
    end

    test "entry contains timestamp" do
      text = "MRN: 12345678"
      {_redacted, manifest} = Redactor.redact_with_manifest(text)

      {:ok, entry} = Audit.log_redaction(manifest)

      assert %DateTime{} = entry.timestamp
    end

    test "entry metadata contains mode" do
      text = "MRN: 12345678"
      {_redacted, manifest} = Redactor.redact_with_manifest(text, mode: :aggressive)

      {:ok, entry} = Audit.log_redaction(manifest)

      assert entry.metadata.mode == :aggressive
    end

    test "works with nil operator and session" do
      text = "MRN: 12345678"
      {_redacted, manifest} = Redactor.redact_with_manifest(text)

      {:ok, entry} = Audit.log_redaction(manifest)

      assert entry.operator_id == nil
      assert entry.session_id == nil
    end
  end

  describe "log_validation/5" do
    test "logs safe validation result" do
      result = {:safe, %{message: "No PHI"}}

      {:ok, entry} = Audit.log_validation(result, :validate_input, "user_1", "sess_1")

      assert entry.operation == :validate_input
      assert entry.metadata.outcome == :safe
      assert entry.redaction_count == 0
    end

    test "logs detected validation result" do
      result = {:detected, %{
        confidence: 0.95,
        patterns_matched: [:mrn, :dob],
        metadata: %{detection_count: 2}
      }}

      {:ok, entry} = Audit.log_validation(result, :validate_output)

      assert entry.metadata.outcome == :detected
      assert :mrn in entry.redaction_types
      assert :dob in entry.redaction_types
      assert entry.redaction_count == 2
    end

    test "includes input hash when provided" do
      result = {:safe, %{}}
      hash = Audit.hash_input("some text")

      {:ok, entry} = Audit.log_validation(result, :validate_input, nil, nil, hash)

      assert entry.input_hash == hash
    end
  end

  describe "log_error/4" do
    test "logs error without exposing content" do
      {:ok, entry} = Audit.log_error(:redact, :timeout, "user_1", "sess_1")

      assert entry.operation == :redact
      assert entry.metadata.outcome == :error
      assert entry.metadata.error == "timeout"
    end

    test "handles exception structs" do
      error = %RuntimeError{message: "Something went wrong"}

      {:ok, entry} = Audit.log_error(:validate_input, error)

      assert entry.metadata.outcome == :error
      assert is_binary(entry.metadata.error)
    end

    test "truncates long error messages" do
      long_error = String.duplicate("a", 500)

      {:ok, entry} = Audit.log_error(:redact, long_error)

      assert String.length(entry.metadata.error) <= 200
    end
  end

  describe "telemetry_events/0" do
    test "returns list of telemetry event names" do
      events = Audit.telemetry_events()

      assert is_list(events)
      assert [:medlum_llm, :guardrails, :redaction] in events
      assert [:medlum_llm, :guardrails, :validation] in events
      assert [:medlum_llm, :guardrails, :error] in events
    end
  end

  describe "hash_input/1" do
    test "returns SHA256 hash of text" do
      hash = Audit.hash_input("test input")

      assert is_binary(hash)
      assert String.length(hash) == 64
      assert Regex.match?(~r/^[a-f0-9]+$/, hash)
    end

    test "same input produces same hash" do
      hash1 = Audit.hash_input("same text")
      hash2 = Audit.hash_input("same text")

      assert hash1 == hash2
    end

    test "different input produces different hash" do
      hash1 = Audit.hash_input("text 1")
      hash2 = Audit.hash_input("text 2")

      refute hash1 == hash2
    end

    test "handles empty string" do
      hash = Audit.hash_input("")

      assert is_binary(hash)
      assert String.length(hash) == 64
    end

    test "handles unicode" do
      hash = Audit.hash_input("こんにちは")

      assert is_binary(hash)
      assert String.length(hash) == 64
    end
  end

  describe "telemetry integration" do
    setup do
      test_pid = self()

      :telemetry.attach(
        "test-handler-#{inspect(self())}",
        [:medlum_llm, :guardrails, :redaction],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-handler-#{inspect(self())}")
      end)

      :ok
    end

    test "log_redaction emits telemetry event" do
      text = "MRN: 12345678"
      {_redacted, manifest} = Redactor.redact_with_manifest(text)

      Audit.log_redaction(manifest, "user_1", "sess_1")

      assert_receive {:telemetry, [:medlum_llm, :guardrails, :redaction], measurements, metadata}
      assert measurements.count == 1
      assert metadata.operator_id == "user_1"
      assert metadata.session_id == "sess_1"
    end
  end
end
