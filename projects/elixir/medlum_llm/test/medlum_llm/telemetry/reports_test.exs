defmodule MedlumLlm.Telemetry.ReportsTest do
  @moduledoc """
  Tests for the MedlumLlm.Telemetry.Reports module.
  """
  use ExUnit.Case

  alias MedlumLlm.Telemetry.Reports
  alias CrucibleTelemetry.{Experiment, Store}

  setup do
    # Start a test experiment with sample data
    {:ok, experiment} =
      Experiment.start(
        name: "reports_test_#{System.unique_integer([:positive])}",
        hypothesis: "Test report generation",
        condition: "test"
      )

    # Insert sample evaluation events
    events = [
      create_sample_event(experiment, :biomistral_7b, true, 1200.0),
      create_sample_event(experiment, :biomistral_7b, true, 1100.0),
      create_sample_event(experiment, :biomistral_7b, false, 1300.0),
      create_sample_event(experiment, :openbio_8b, true, 800.0),
      create_sample_event(experiment, :openbio_8b, true, 850.0)
    ]

    for event <- events do
      Store.insert(experiment.id, event)
    end

    on_exit(fn ->
      Experiment.cleanup(experiment.id)
    end)

    {:ok, experiment: experiment}
  end

  describe "generate/3 with markdown format" do
    test "generates markdown report", %{experiment: experiment} do
      {:ok, report} =
        Reports.generate(experiment.id, :markdown,
          title: "Test Report"
        )

      assert is_binary(report)
      assert String.contains?(report, "# Test Report")
      assert String.contains?(report, "Generated:")
      assert String.contains?(report, "## Summary")
    end

    test "includes model metrics table", %{experiment: experiment} do
      {:ok, report} = Reports.generate(experiment.id, :markdown)

      assert String.contains?(report, "| Experiment |")
      assert String.contains?(report, "| Model |")
      assert String.contains?(report, "| Accuracy |")
      assert String.contains?(report, "biomistral_7b")
      assert String.contains?(report, "openbio_8b")
    end

    test "includes environment section when requested", %{experiment: experiment} do
      # Add environment to experiment metadata
      {:ok, exp} = Experiment.get(experiment.id)
      updated_metadata = Map.put(exp.metadata, :environment, %{elixir_version: "1.17.0", otp_version: "27.0"})

      :ets.insert(:crucible_telemetry_experiments, {experiment.id, %{exp | metadata: updated_metadata}})

      {:ok, report} =
        Reports.generate(experiment.id, :markdown,
          include_environment: true
        )

      assert String.contains?(report, "## Environment")
      assert String.contains?(report, "Elixir Version")
    end
  end

  describe "generate/3 with latex format" do
    test "generates latex table", %{experiment: experiment} do
      {:ok, report} =
        Reports.generate(experiment.id, :latex,
          title: "Evaluation Results"
        )

      assert is_binary(report)
      assert String.contains?(report, "\\begin{table}")
      assert String.contains?(report, "\\end{table}")
      assert String.contains?(report, "\\toprule")
      assert String.contains?(report, "\\bottomrule")
    end

    test "includes caption with title", %{experiment: experiment} do
      {:ok, report} =
        Reports.generate(experiment.id, :latex,
          title: "MedQA Results"
        )

      assert String.contains?(report, "\\caption{MedQA Results}")
    end

    test "escapes percent sign in CI header", %{experiment: experiment} do
      {:ok, report} = Reports.generate(experiment.id, :latex)

      assert String.contains?(report, "95\\%")
    end
  end

  describe "generate/3 with html format" do
    test "generates html document", %{experiment: experiment} do
      {:ok, report} =
        Reports.generate(experiment.id, :html,
          title: "Test Report"
        )

      assert is_binary(report)
      assert String.contains?(report, "<!DOCTYPE html>")
      assert String.contains?(report, "<title>Test Report</title>")
      assert String.contains?(report, "</html>")
    end

    test "includes styled table", %{experiment: experiment} do
      {:ok, report} = Reports.generate(experiment.id, :html)

      assert String.contains?(report, "<table>")
      assert String.contains?(report, "<thead>")
      assert String.contains?(report, "<tbody>")
      assert String.contains?(report, "<style>")
    end
  end

  describe "generate/3 with json format" do
    test "generates valid json", %{experiment: experiment} do
      {:ok, report} =
        Reports.generate(experiment.id, :json,
          title: "Test Report"
        )

      assert is_binary(report)
      assert {:ok, _} = Jason.decode(report)
    end

    test "includes experiment data in json", %{experiment: experiment} do
      {:ok, report} = Reports.generate(experiment.id, :json)

      {:ok, data} = Jason.decode(report)

      assert Map.has_key?(data, "experiments")
      assert is_list(data["experiments"])

      exp_data = hd(data["experiments"])
      assert Map.has_key?(exp_data, "id")
      assert Map.has_key?(exp_data, "name")
      assert Map.has_key?(exp_data, "model_metrics")
    end

    test "includes title and timestamp", %{experiment: experiment} do
      {:ok, report} =
        Reports.generate(experiment.id, :json,
          title: "JSON Report"
        )

      {:ok, data} = Jason.decode(report)

      assert data["title"] == "JSON Report"
      assert Map.has_key?(data, "generated_at")
    end
  end

  describe "generate/3 with multiple experiments" do
    test "combines multiple experiments in report", %{experiment: experiment} do
      # Create second experiment
      {:ok, experiment2} =
        Experiment.start(
          name: "reports_test_2_#{System.unique_integer([:positive])}",
          hypothesis: "Second test",
          condition: "control"
        )

      events = [
        create_sample_event(experiment2, :gpt4, true, 500.0),
        create_sample_event(experiment2, :gpt4, true, 550.0)
      ]

      for event <- events do
        Store.insert(experiment2.id, event)
      end

      on_exit(fn ->
        Experiment.cleanup(experiment2.id)
      end)

      {:ok, report} = Reports.generate([experiment.id, experiment2.id], :markdown)

      assert String.contains?(report, experiment.name)
      assert String.contains?(report, experiment2.name)
      assert String.contains?(report, "biomistral_7b")
      assert String.contains?(report, "gpt4")
    end
  end

  describe "comparison_table/3" do
    test "generates comparison table in markdown", %{experiment: experiment} do
      {:ok, exp2} =
        Experiment.start(
          name: "comparison_test_#{System.unique_integer([:positive])}",
          condition: "treatment"
        )

      events = [create_sample_event(exp2, :test_model, true, 100.0)]

      for event <- events do
        Store.insert(exp2.id, event)
      end

      on_exit(fn ->
        Experiment.cleanup(exp2.id)
      end)

      {:ok, table} =
        Reports.comparison_table([experiment.id, exp2.id], :markdown,
          title: "A/B Comparison"
        )

      assert String.contains?(table, "## A/B Comparison")
      assert String.contains?(table, "| Condition |")
      assert String.contains?(table, "test")
      assert String.contains?(table, "treatment")
    end

    test "generates comparison table in latex", %{experiment: experiment} do
      {:ok, table} = Reports.comparison_table([experiment.id], :latex)

      assert String.contains?(table, "\\begin{table}")
      assert String.contains?(table, "Condition")
    end
  end

  describe "baseline_comparison/2" do
    test "generates baseline comparison section", %{experiment: experiment} do
      {:ok, section} =
        Reports.baseline_comparison(experiment.id,
          dataset: "medqa"
        )

      assert String.contains?(section, "## Baseline Comparison")
      assert String.contains?(section, "| Model |")
      # Should include pre-defined baselines
      assert String.contains?(section, "GPT-4")
    end

    test "includes experiment models in comparison", %{experiment: experiment} do
      {:ok, section} = Reports.baseline_comparison(experiment.id, dataset: "medqa")

      assert String.contains?(section, "biomistral_7b")
      assert String.contains?(section, "openbio_8b")
    end
  end

  describe "error handling" do
    test "returns error for non-existent experiment" do
      {:error, _} = Reports.generate("non_existent_id", :markdown)
    end

    test "returns error for unsupported format", %{experiment: experiment} do
      {:error, :unsupported_format} = Reports.generate(experiment.id, :pdf)
    end
  end

  # Helper function to create test events

  defp create_sample_event(experiment, model, correct, latency_ms) do
    %{
      event_id: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower),
      event_name: [:medlum_llm, :eval, :sample, :stop],
      timestamp: System.system_time(:microsecond),
      experiment_id: experiment.id,
      experiment_name: experiment.name,
      condition: experiment.condition,
      tags: experiment.tags,
      measurements: %{
        duration: round(latency_ms * 1_000_000),
        input_tokens: 150,
        output_tokens: 25,
        tokens_per_second: 25.0
      },
      metadata: %{
        run_id: "run_#{System.unique_integer([:positive])}",
        model: model,
        sample_idx: System.unique_integer([:positive]),
        predicted: if(correct, do: "A", else: "B"),
        correct_answer: "A",
        correct: correct
      },
      latency_ms: latency_ms,
      cost_usd: 0.001,
      success: true
    }
  end
end
