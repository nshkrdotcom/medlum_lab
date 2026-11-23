defmodule MedlumLlm.ExamplesTest do
  @moduledoc """
  Verify that NSAI example files exist and have valid syntax.

  These examples demonstrate the MedlumLlm functionality added in prompts 180-189:
  - Datasets wrapper
  - Medical metrics
  - Benchmarks and baselines
  - CVL verification
  - End-to-end evaluation pipeline
  """
  use ExUnit.Case, async: true

  @examples_dir "examples"
  @expected_examples [
    "datasets_example.exs",
    "metrics_example.exs",
    "benchmark_example.exs",
    "cvl_example.exs",
    "evaluation_pipeline.exs"
  ]

  describe "NSAI example files" do
    test "all expected examples exist" do
      for example <- @expected_examples do
        path = Path.join(@examples_dir, example)
        assert File.exists?(path), "Missing example: #{path}"
      end
    end

    test "all examples have valid Elixir syntax" do
      for example <- @expected_examples do
        path = Path.join(@examples_dir, example)

        if File.exists?(path) do
          content = File.read!(path)

          # Try to parse the file
          result = Code.string_to_quoted(content, file: path)

          case result do
            {:ok, _ast} ->
              assert true

            {:error, {meta, message, _}} when is_list(meta) ->
              line = Keyword.get(meta, :line, "?")
              flunk("Syntax error in #{path} at line #{line}: #{message}")

            {:error, {line, message, _}} when is_integer(line) ->
              flunk("Syntax error in #{path} at line #{line}: #{message}")

            {:error, error} ->
              flunk("Syntax error in #{path}: #{inspect(error)}")
          end
        end
      end
    end

    test "all examples have shebang and description comment" do
      for example <- @expected_examples do
        path = Path.join(@examples_dir, example)

        if File.exists?(path) do
          content = File.read!(path)
          lines = String.split(content, "\n", parts: 5)

          # Check shebang
          assert String.starts_with?(hd(lines), "#!/usr/bin/env elixir"),
                 "#{path} should start with shebang"

          # Check for description comment
          has_description =
            Enum.any?(lines, fn line ->
              String.contains?(line, "Example") or
                String.contains?(line, "example") or
                String.contains?(line, "Run with:")
            end)

          assert has_description, "#{path} should have a description comment"
        end
      end
    end

    test "all examples have run instructions" do
      for example <- @expected_examples do
        path = Path.join(@examples_dir, example)

        if File.exists?(path) do
          content = File.read!(path)

          assert String.contains?(content, "mix run"),
                 "#{path} should include 'mix run' instructions"
        end
      end
    end
  end

  describe "example content validation" do
    test "datasets_example.exs references correct modules" do
      path = Path.join(@examples_dir, "datasets_example.exs")

      if File.exists?(path) do
        content = File.read!(path)

        assert String.contains?(content, "MedlumLlm.Datasets"),
               "Should reference Datasets module"

        assert String.contains?(content, "Config"),
               "Should reference Config"
      end
    end

    test "metrics_example.exs references correct modules" do
      path = Path.join(@examples_dir, "metrics_example.exs")

      if File.exists?(path) do
        content = File.read!(path)

        assert String.contains?(content, "MedicalMetrics"),
               "Should reference MedicalMetrics module"

        assert String.contains?(content, "wilson_ci") or String.contains?(content, "Wilson"),
               "Should demonstrate Wilson CI"

        assert String.contains?(content, "hallucination"),
               "Should demonstrate hallucination metrics"
      end
    end

    test "benchmark_example.exs references correct modules" do
      path = Path.join(@examples_dir, "benchmark_example.exs")

      if File.exists?(path) do
        content = File.read!(path)

        assert String.contains?(content, "Benchmarks"),
               "Should reference Benchmarks module"

        assert String.contains?(content, "Baselines"),
               "Should reference Baselines module"

        assert String.contains?(content, "Prompts"),
               "Should reference Prompts module"
      end
    end

    test "cvl_example.exs references correct modules" do
      path = Path.join(@examples_dir, "cvl_example.exs")

      if File.exists?(path) do
        content = File.read!(path)

        assert String.contains?(content, "Verifier"),
               "Should reference Verifier module"

        assert String.contains?(content, "Consensus"),
               "Should reference Consensus module"

        assert String.contains?(content, "MedicationAgent"),
               "Should reference MedicationAgent"

        assert String.contains?(content, "LabAgent"),
               "Should reference LabAgent"
      end
    end

    test "evaluation_pipeline.exs demonstrates end-to-end workflow" do
      path = Path.join(@examples_dir, "evaluation_pipeline.exs")

      if File.exists?(path) do
        content = File.read!(path)

        # Should have clear step markers
        assert String.contains?(content, "Step 1"),
               "Should have numbered steps"

        assert String.contains?(content, "Datasets"),
               "Should load datasets"

        assert String.contains?(content, "Benchmarks"),
               "Should use benchmarks"

        assert String.contains?(content, "MedicalMetrics"),
               "Should calculate metrics"

        assert String.contains?(content, "CVL") or String.contains?(content, "Verifier"),
               "Should include CVL verification"

        assert String.contains?(content, "Summary"),
               "Should produce summary report"
      end
    end
  end

  describe "mix aliases" do
    test "example aliases are defined in mix.exs" do
      # Read mix.exs and check for aliases
      mix_content = File.read!("mix.exs")

      assert String.contains?(mix_content, "example.datasets"),
             "Should have example.datasets alias"

      assert String.contains?(mix_content, "example.metrics"),
             "Should have example.metrics alias"

      assert String.contains?(mix_content, "example.benchmarks"),
             "Should have example.benchmarks alias"

      assert String.contains?(mix_content, "example.cvl"),
             "Should have example.cvl alias"

      assert String.contains?(mix_content, "example.pipeline"),
             "Should have example.pipeline alias"

      assert String.contains?(mix_content, "examples.nsai"),
             "Should have examples.nsai alias to run all"
    end
  end
end
