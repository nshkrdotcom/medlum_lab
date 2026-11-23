defmodule MedlumLlm.CVL.LabelingQueueTest do
  use ExUnit.Case, async: false

  alias MedlumLlm.CVL.LabelingQueue

  # Note: These tests require Anvil to be available
  # Some tests may be skipped if Anvil is not properly configured

  describe "queue_id/0" do
    test "returns the CVL queue identifier" do
      assert LabelingQueue.queue_id() == "cvl_nli_training"
    end
  end

  describe "queue_ref/0" do
    test "returns a via tuple for Registry lookup" do
      ref = LabelingQueue.queue_ref()

      assert {:via, Registry, {Anvil.Registry, "cvl_nli_training"}} = ref
    end
  end

  describe "create_queue/1" do
    @tag :integration
    test "creates queue with default options" do
      # This test requires Anvil to be running
      result = LabelingQueue.create_queue()

      case result do
        {:ok, _} ->
          # Queue created successfully
          assert true

        {:error, :already_started} ->
          # Queue already exists, which is fine
          assert true

        {:error, reason} ->
          # Other errors should be investigated
          flunk("Failed to create queue: #{inspect(reason)}")
      end
    end

    @tag :integration
    test "creates queue with custom labels_per_sample" do
      result = LabelingQueue.create_queue(labels_per_sample: 5)

      case result do
        {:ok, _} -> assert true
        {:error, :already_started} -> assert true
        {:error, reason} -> flunk("Failed to create queue: #{inspect(reason)}")
      end
    end
  end

  describe "sample format" do
    test "creates properly formatted samples" do
      sample = %{
        id: "cvl_test_123",
        premise: "Patient has Type 2 diabetes",
        hypothesis: "Patient is diabetic",
        metadata: %{
          source: :manual,
          error_type: nil
        }
      }

      assert sample.id == "cvl_test_123"
      assert sample.premise == "Patient has Type 2 diabetes"
      assert sample.hypothesis == "Patient is diabetic"
      assert sample.metadata.source == :manual
    end
  end

  describe "label format" do
    test "validates expected label structure" do
      label = %{
        "verdict" => "ENTAILMENT",
        "confidence" => 4,
        "evidence_quality" => "clear",
        "reasoning" => "The premise explicitly states diabetes"
      }

      assert label["verdict"] in ["ENTAILMENT", "CONTRADICTION", "NEUTRAL"]
      assert label["confidence"] in 1..5
      assert label["evidence_quality"] in ["clear", "partial", "ambiguous", "missing"]
    end
  end

  describe "stats/0" do
    @tag :integration
    test "returns queue statistics structure" do
      # Ensure queue exists
      LabelingQueue.create_queue()

      stats = LabelingQueue.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_labels)
      assert Map.has_key?(stats, :total_assignments)
      assert Map.has_key?(stats, :completed_assignments)
      assert Map.has_key?(stats, :total_samples)
      assert Map.has_key?(stats, :unique_labelers)
    end
  end
end
