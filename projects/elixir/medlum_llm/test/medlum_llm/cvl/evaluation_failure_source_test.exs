defmodule MedlumLlm.CVL.EvaluationFailureSourceTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.EvaluationFailureSource

  @test_results_dir Path.join(System.tmp_dir!(), "cvl_test_results_#{System.unique_integer()}")

  setup do
    File.mkdir_p!(@test_results_dir)

    on_exit(fn ->
      File.rm_rf!(@test_results_dir)
    end)

    :ok
  end

  describe "init/1" do
    test "initializes with required results_dir" do
      {:ok, state} = EvaluationFailureSource.init(results_dir: @test_results_dir)

      assert state.results_dir == @test_results_dir
      assert state.filters == [:error, :incorrect, :low_confidence]
      assert state.min_confidence == 0.5
    end

    test "accepts custom filters" do
      {:ok, state} =
        EvaluationFailureSource.init(
          results_dir: @test_results_dir,
          filters: [:incorrect, :contradiction]
        )

      assert state.filters == [:incorrect, :contradiction]
    end

    test "accepts custom min_confidence" do
      {:ok, state} =
        EvaluationFailureSource.init(
          results_dir: @test_results_dir,
          min_confidence: 0.3
        )

      assert state.min_confidence == 0.3
    end

    test "raises when results_dir is missing" do
      assert_raise KeyError, fn ->
        EvaluationFailureSource.init([])
      end
    end
  end

  describe "fetch/1" do
    test "returns :done when no files exist" do
      {:ok, state} = EvaluationFailureSource.init(results_dir: @test_results_dir)

      assert {:done, _state} = EvaluationFailureSource.fetch(state)
    end

    test "reads valid JSON files and returns samples as batch" do
      write_test_json("run1.json", valid_eval_result())

      {:ok, state} = EvaluationFailureSource.init(results_dir: @test_results_dir)

      assert {:ok, samples, _new_state} = EvaluationFailureSource.fetch(state)
      assert is_list(samples)
      assert length(samples) >= 1

      sample = hd(samples)
      assert sample.id =~ "cvl_"
      assert sample.error_type == :incorrect
      assert sample.source_document == "Test context"
    end

    test "filters by error type" do
      write_test_json("run1.json", eval_result_with_errors([
        error_entry("incorrect", 0),
        error_entry("error", 1),
        error_entry("timeout", 2)
      ]))

      # Only include :incorrect errors
      {:ok, state} = EvaluationFailureSource.init(
        results_dir: @test_results_dir,
        filters: [:incorrect]
      )

      # Should only get the incorrect error
      {:ok, samples, state} = EvaluationFailureSource.fetch(state)
      assert length(samples) == 1
      assert hd(samples).error_type == :incorrect

      # No more samples
      assert {:done, _} = EvaluationFailureSource.fetch(state)
    end

    test "handles malformed JSON gracefully" do
      File.write!(Path.join(@test_results_dir, "bad.json"), "not valid json")
      write_test_json("good.json", valid_eval_result())

      {:ok, state} = EvaluationFailureSource.init(results_dir: @test_results_dir)

      # Should skip bad file and return from good file
      {:ok, samples, _} = EvaluationFailureSource.fetch(state)
      assert length(samples) >= 1
      assert hd(samples).error_type == :incorrect
    end

    test "handles empty errors list" do
      write_test_json("empty.json", %{
        "run" => %{"id" => "run1", "benchmark" => "test"},
        "errors" => []
      })

      {:ok, state} = EvaluationFailureSource.init(results_dir: @test_results_dir)

      assert {:done, _} = EvaluationFailureSource.fetch(state)
    end

    test "iterates through multiple files" do
      write_test_json("run1.json", eval_result_with_run_id("run1"))
      write_test_json("run2.json", eval_result_with_run_id("run2"))

      {:ok, state} = EvaluationFailureSource.init(results_dir: @test_results_dir)

      # Should get all samples in one batch
      {:ok, samples, _state} = EvaluationFailureSource.fetch(state)

      # Should have samples from both runs
      run_ids = Enum.map(samples, & &1.eval_run_id)
      assert "run1" in run_ids
      assert "run2" in run_ids
    end
  end

  describe "cleanup/1" do
    test "returns :ok" do
      {:ok, state} = EvaluationFailureSource.init(results_dir: @test_results_dir)
      assert :ok = EvaluationFailureSource.cleanup(state)
    end
  end

  # Helper functions

  defp write_test_json(filename, data) do
    path = Path.join(@test_results_dir, filename)
    File.write!(path, Jason.encode!(data))
  end

  defp valid_eval_result do
    %{
      "run" => %{
        "id" => "test_run_1",
        "benchmark" => "medqa_zero_shot"
      },
      "errors" => [
        %{
          "sample_idx" => 0,
          "sample_id" => "medqa_0001",
          "error" => "incorrect",
          "model" => "openbio_8b",
          "context" => "Test context",
          "model_output" => "Test output",
          "expected" => "A",
          "predicted" => "B"
        }
      ]
    }
  end

  defp error_entry(error_type, idx) do
    %{
      "sample_idx" => idx,
      "sample_id" => "sample_#{idx}",
      "error" => error_type,
      "model" => "test_model",
      "context" => "Context #{idx}",
      "model_output" => "Output #{idx}",
      "expected" => "A",
      "predicted" => "B"
    }
  end

  defp eval_result_with_errors(errors) do
    %{
      "run" => %{
        "id" => "test_run",
        "benchmark" => "test_bench"
      },
      "errors" => errors
    }
  end

  defp eval_result_with_run_id(run_id) do
    %{
      "run" => %{
        "id" => run_id,
        "benchmark" => "test_bench"
      },
      "errors" => [
        %{
          "sample_idx" => 0,
          "sample_id" => "sample_0",
          "error" => "incorrect",
          "model" => "test_model",
          "context" => "Context",
          "model_output" => "Output",
          "expected" => "A",
          "predicted" => "B"
        }
      ]
    }
  end
end
