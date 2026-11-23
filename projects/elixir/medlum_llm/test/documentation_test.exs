defmodule MedlumLlm.DocumentationTest do
  @moduledoc """
  Verify documentation completeness.
  """
  use ExUnit.Case

  @required_files [
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
    "guides/getting_started.md",
    "guides/cvl.md",
    "guides/evaluation.md",
    "guides/datasets.md"
  ]

  describe "documentation files" do
    test "all required files exist" do
      for file <- @required_files do
        assert File.exists?(file), "Missing documentation file: #{file}"
      end
    end

    test "README.md has required sections" do
      readme = File.read!("README.md")

      assert readme =~ "## Features", "README missing Features section"
      assert readme =~ "## Installation", "README missing Installation section"
      assert readme =~ "## Quick Start", "README missing Quick Start section"
      assert readme =~ "CVL", "README missing CVL reference"
      assert readme =~ "## Examples", "README missing Examples section"
      assert readme =~ "## Documentation", "README missing Documentation section"
    end

    test "README.md includes all major features" do
      readme = File.read!("README.md")

      # Core features
      assert readme =~ "Chat & Embeddings", "README missing Chat & Embeddings"
      assert readme =~ "Clinical Verification Layer", "README missing CVL section"
      assert readme =~ "Medical Evaluation", "README missing Medical Evaluation"

      # CVL agents
      assert readme =~ "MedicationAgent", "README missing MedicationAgent"
      assert readme =~ "LabAgent", "README missing LabAgent"
      assert readme =~ "OntologyAgent", "README missing OntologyAgent"
      assert readme =~ "TemporalAgent", "README missing TemporalAgent"
      assert readme =~ "DifferentialAgent", "README missing DifferentialAgent"

      # NSAI integration
      assert readme =~ "hf_datasets_ex", "README missing hf_datasets_ex"
      assert readme =~ "eval_ex", "README missing eval_ex"
      assert readme =~ "crucible_bench", "README missing crucible_bench"
    end

    test "CHANGELOG.md has version 0.2.0" do
      changelog = File.read!("CHANGELOG.md")

      assert changelog =~ "[0.2.0]", "CHANGELOG missing version 0.2.0"
      assert changelog =~ "2026-01-25", "CHANGELOG missing release date"
      assert changelog =~ "NSAI", "CHANGELOG missing NSAI reference"
      assert changelog =~ "CVL", "CHANGELOG missing CVL section"
    end

    test "CHANGELOG.md has correct sections" do
      changelog = File.read!("CHANGELOG.md")

      assert changelog =~ "### Added", "CHANGELOG missing Added section"
      assert changelog =~ "Clinical Verification Layer", "CHANGELOG missing CVL section"
      assert changelog =~ "Medical Datasets", "CHANGELOG missing Datasets section"
      assert changelog =~ "Medical Benchmarks", "CHANGELOG missing Benchmarks section"
    end

    test "getting_started.md has essential sections" do
      getting_started = File.read!("guides/getting_started.md")

      assert getting_started =~ "## Prerequisites", "Getting started missing Prerequisites"
      assert getting_started =~ "## Installation", "Getting started missing Installation"
      assert getting_started =~ "## Configuration", "Getting started missing Configuration"
      assert getting_started =~ "Ollama", "Getting started missing Ollama setup"
    end

    test "cvl.md has essential sections" do
      cvl = File.read!("guides/cvl.md")

      assert cvl =~ "Medication Agent", "CVL guide missing Medication Agent"
      assert cvl =~ "Lab Agent", "CVL guide missing Lab Agent"
      assert cvl =~ "Ontology Agent", "CVL guide missing Ontology Agent"
      assert cvl =~ "Temporal Agent", "CVL guide missing Temporal Agent"
      assert cvl =~ "Differential Agent", "CVL guide missing Differential Agent"
      assert cvl =~ "Verdicts", "CVL guide missing Verdicts section"
    end

    test "evaluation.md has essential sections" do
      evaluation = File.read!("guides/evaluation.md")

      assert evaluation =~ "Metrics", "Evaluation guide missing Metrics"
      assert evaluation =~ "accuracy", "Evaluation guide missing accuracy"
      assert evaluation =~ "Wilson", "Evaluation guide missing Wilson CI"
    end
  end

  describe "module documentation" do
    @public_modules [
      MedlumLlm,
      MedlumLlm.Chat,
      MedlumLlm.Embedder,
      MedlumLlm.Datasets,
      MedlumLlm.Eval.MedicalMetrics,
      MedlumLlm.Eval.Benchmarks,
      MedlumLlm.Eval.Baselines,
      MedlumLlm.Eval.Prompts,
      MedlumLlm.CVL.Agent,
      MedlumLlm.CVL.MedicationAgent,
      MedlumLlm.CVL.LabAgent,
      MedlumLlm.CVL.OntologyAgent,
      MedlumLlm.CVL.TemporalAgent,
      MedlumLlm.CVL.DifferentialAgent
    ]

    test "all public modules have @moduledoc" do
      for module <- @public_modules do
        case Code.ensure_loaded(module) do
          {:module, _} ->
            case Code.fetch_docs(module) do
              {:docs_v1, _, :elixir, _, %{"en" => moduledoc}, _, _} ->
                assert moduledoc != nil, "#{module} has nil @moduledoc"
                assert String.length(moduledoc) > 50, "#{module} has too short @moduledoc"

              {:docs_v1, _, :elixir, _, :none, _, _} ->
                flunk("#{module} has no @moduledoc")

              {:docs_v1, _, :elixir, _, :hidden, _, _} ->
                # Hidden modules are acceptable
                :ok

              {:error, _} ->
                # Module may not have docs, skip
                :ok
            end

          {:error, _} ->
            # Module may not exist yet, skip
            :ok
        end
      end
    end
  end

  describe "examples" do
    @nsai_examples [
      "examples/datasets_example.exs",
      "examples/metrics_example.exs",
      "examples/benchmark_example.exs",
      "examples/cvl_example.exs",
      "examples/evaluation_pipeline.exs"
    ]

    test "NSAI examples exist" do
      for example <- @nsai_examples do
        assert File.exists?(example), "Missing example file: #{example}"
      end
    end

    test "examples have proper structure" do
      for example <- @nsai_examples do
        content = File.read!(example)

        # Check for shebang or Mix.install
        has_header = content =~ "#!/usr/bin/env" or content =~ "Mix.install"
        assert has_header, "#{example} missing shebang or Mix.install"

        # Check for module references
        assert content =~ "MedlumLlm", "#{example} missing MedlumLlm reference"
      end
    end
  end

  describe "mix.exs configuration" do
    test "has correct version" do
      mix_exs = File.read!("mix.exs")

      assert mix_exs =~ ~s(@version "0.2.0"), "mix.exs missing version 0.2.0"
    end

    test "has hexdocs configuration" do
      mix_exs = File.read!("mix.exs")

      assert mix_exs =~ "defp docs do", "mix.exs missing docs function"
      assert mix_exs =~ "groups_for_modules", "mix.exs missing groups_for_modules"
      assert mix_exs =~ "extras:", "mix.exs missing extras"
    end

    test "has NSAI example aliases" do
      mix_exs = File.read!("mix.exs")

      assert mix_exs =~ "example.datasets", "mix.exs missing example.datasets alias"
      assert mix_exs =~ "example.cvl", "mix.exs missing example.cvl alias"
      assert mix_exs =~ "examples.nsai", "mix.exs missing examples.nsai alias"
    end
  end

  describe "LICENSE" do
    test "LICENSE file exists and is MIT" do
      license = File.read!("LICENSE")

      assert license =~ "MIT License", "LICENSE is not MIT"
      assert license =~ "Permission is hereby granted", "LICENSE missing permission grant"
      assert license =~ "WITHOUT WARRANTY", "LICENSE missing warranty disclaimer"
    end
  end
end
