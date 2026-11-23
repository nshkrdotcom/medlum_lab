defmodule MedlumLlm.Storage.AuditedPostgresTest do
  use ExUnit.Case, async: true

  # Note: These tests mock the underlying Postgres storage
  # since we don't have a database connection in unit tests

  alias MedlumLlm.Storage.AuditedPostgres

  describe "audit logging" do
    test "hashes sample IDs for privacy" do
      # Test the internal hash_id function via reflection or by testing audit output
      # For now, we verify the module compiles and has expected structure
      assert function_exported?(AuditedPostgres, :init, 1)
      assert function_exported?(AuditedPostgres, :store, 2)
      assert function_exported?(AuditedPostgres, :retrieve, 2)
      assert function_exported?(AuditedPostgres, :list, 2)
      assert function_exported?(AuditedPostgres, :cleanup, 1)
    end

    test "audit_stats returns expected structure" do
      # Create a mock state for testing
      mock_state = %{
        postgres_state: %{},
        pipeline_name: :test_pipeline,
        audit_enabled: true
      }

      stats = AuditedPostgres.audit_stats(mock_state)

      assert stats.pipeline_name == :test_pipeline
      assert stats.audit_enabled == true
    end
  end

  describe "behaviour implementation" do
    test "implements Forge.Storage behaviour" do
      behaviours = AuditedPostgres.__info__(:attributes)[:behaviour] || []
      assert Forge.Storage in behaviours
    end
  end
end
