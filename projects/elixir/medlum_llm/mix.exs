defmodule MedlumLlm.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/medlum/medlum_llm"

  def project do
    [
      app: :medlum_llm,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      aliases: aliases(),

      # Hex.pm / HexDocs
      name: "MedlumLlm",
      source_url: @source_url,
      homepage_url: "https://medlum.ai"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {MedlumLlm.Application, []}
    ]
  end

  defp deps do
    nsai = "../../../../../North-Shore-AI"
    medlum = ".."

    [
      # === Existing ===
      {:ollixir, "~> 0.1.0"},
      {:jason, "~> 1.4"},

      # === NSAI Evaluation Stack ===
      {:eval_ex, path: "#{nsai}/eval_ex", override: true},
      {:crucible_bench, path: "#{nsai}/crucible_bench", override: true},
      {:crucible_harness, path: "#{nsai}/crucible_harness", override: true},
      {:metrics_ex, path: "#{nsai}/metrics_ex", override: true},

      # === NSAI Data Stack ===
      {:hf_datasets_ex, path: "#{nsai}/hf_datasets_ex", override: true},
      {:datasets_ex, path: "#{nsai}/datasets_ex", override: true},
      {:forge, path: "#{nsai}/forge", override: true, runtime: false},
      {:anvil, path: "#{nsai}/anvil", override: true, runtime: false},
      {:labeling_ir, path: "#{nsai}/labeling_ir", override: true},

      # === NSAI Infrastructure ===
      {:hf_hub, path: "#{nsai}/hf_hub_ex", override: true},
      {:embed_ex, path: "#{nsai}/embed_ex", override: true},
      {:crucible_ensemble, path: "#{nsai}/crucible_ensemble", override: true},
      {:crucible_telemetry, path: "#{nsai}/crucible_telemetry", override: true},
      {:llm_guard, path: "#{nsai}/LlmGuard", override: true},

      # === Medical-Specific (sibling medlum packages) ===
      {:med_ontology_ex, path: "#{medlum}/med_ontology_ex", optional: true, runtime: false},
      {:clinical_ner_ex, path: "#{medlum}/clinical_ner_ex", optional: true, runtime: false},

      # === Transitive dep overrides (resolve version conflicts) ===
      {:telemetry_metrics, "~> 1.0", override: true},

      # === Development and Testing ===
      {:mox, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/logo.png",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE",
        "guides/getting_started.md",
        "guides/cvl.md",
        "guides/evaluation.md",
        "guides/datasets.md",
        "guides/hipaa_compliance.md",
        "guides/redaction.md",
        "guides/cvl_training_pipeline.md",
        "guides/cvl_measurements.md",
        "guides/cvl_labeling.md",
        "guides/cvl_export.md",
        "examples/README.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/,
        Examples: ~r/examples\/.*/
      ],
      groups_for_modules: [
        "Core": [
          MedlumLlm,
          MedlumLlm.Chat,
          MedlumLlm.Embedder,
          MedlumLlm.Models
        ],
        "CVL Agents": [
          MedlumLlm.CVL.Agent,
          MedlumLlm.CVL.MedicationAgent,
          MedlumLlm.CVL.LabAgent,
          MedlumLlm.CVL.OntologyAgent,
          MedlumLlm.CVL.TemporalAgent,
          MedlumLlm.CVL.DifferentialAgent,
          MedlumLlm.CVL.RxNormStub,
          MedlumLlm.CVL.LOINCStub,
          MedlumLlm.CVL.SNOMEDStub,
          MedlumLlm.CVL.ICD10Stub,
          MedlumLlm.CVL.DifferentialDB
        ],
        "CVL Training Pipeline": [
          MedlumLlm.CVL.TrainingPipeline,
          MedlumLlm.CVL.EvaluationFailureSource,
          MedlumLlm.CVL.Stages.NormalizeText,
          MedlumLlm.CVL.Stages.ClaimExtraction,
          MedlumLlm.CVL.Stages.NLIPairGenerator,
          MedlumLlm.CVL.Stages.PIIRedaction,
          MedlumLlm.CVL.Stages.AnvilExport
        ],
        "CVL Measurements": [
          MedlumLlm.CVL.Measurements.MedicationAgent,
          MedlumLlm.CVL.Measurements.LabAgent,
          MedlumLlm.CVL.Measurements.OntologyAgent,
          MedlumLlm.CVL.Measurements.TemporalAgent,
          MedlumLlm.CVL.Measurements.DifferentialAgent,
          MedlumLlm.CVL.Measurements.AgentConsensus,
          MedlumLlm.CVL.Measurements.Confidence
        ],
        "CVL Labeling": [
          MedlumLlm.CVL.LabelingSchema,
          MedlumLlm.CVL.LabelingQueue,
          MedlumLlm.CVL.SampleLoader,
          MedlumLlm.CVL.ExportPipeline,
          MedlumLlm.CVL.ForgeBridge,
          MedlumLlm.CVL.SchemaVersions,
          MedlumLlm.CVL.LabelingGuidelines
        ],
        "Guardrails": [
          MedlumLlm.Guardrails,
          MedlumLlm.Guardrails.Redactor,
          MedlumLlm.Guardrails.Audit
        ],
        "Detectors": [
          MedlumLlm.Detectors.ClinicalPII,
          MedlumLlm.Detectors.ClinicalPII.Patterns
        ],
        "Storage": [
          MedlumLlm.Storage.AuditedPostgres
        ],
        "HubClient": [
          MedlumLlm.HubClient,
          MedlumLlm.HubClient.Manifest,
          MedlumLlm.HubClient.Warmup,
          MedlumLlm.HubClient.OllamaWarmup,
          MedlumLlm.HubClient.HfWarmup
        ],
        "Datasets": [
          MedlumLlm.Datasets,
          MedlumLlm.Datasets.Config,
          MedlumLlm.Datasets.Preprocessor
        ],
        "Evaluation": [
          MedlumLlm.Eval.Benchmarks,
          MedlumLlm.Eval.Baselines,
          MedlumLlm.Eval.Prompts,
          MedlumLlm.Eval.Experiments,
          MedlumLlm.Eval.MedicalMetrics
        ],
        "Integration": [
          MedlumLlm.Integration.Error,
          MedlumLlm.Integration.VersionCheck
        ]
      ],
      nest_modules_by_prefix: [
        MedlumLlm.CVL,
        MedlumLlm.Eval,
        MedlumLlm.Datasets,
        MedlumLlm.Models,
        MedlumLlm.Guardrails,
        MedlumLlm.Detectors,
        MedlumLlm.HubClient,
        MedlumLlm.Integration
      ],
      source_url: @source_url
    ]
  end

  defp description do
    """
    Medical LLM library for Elixir using Ollama/Ollixir.
    Supports BioMistral, OpenBioLLM, Meditron, and clinical embeddings.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp aliases do
    [
      test: "test --exclude integration",
      "test.all": "test --include integration",
      "test.integration": "test --only integration",
      "deps.nsai": ["deps.get", "deps.compile"],
      "check.nsai": &check_nsai_versions/1,
      # NSAI Example runners (prompts 180-189)
      "example.datasets": ["run examples/datasets_example.exs"],
      "example.metrics": ["run examples/metrics_example.exs"],
      "example.benchmarks": ["run examples/benchmark_example.exs"],
      "example.cvl": ["run examples/cvl_example.exs"],
      "example.pipeline": ["run examples/evaluation_pipeline.exs"],
      "examples.nsai": [
        "example.datasets",
        "example.metrics",
        "example.benchmarks",
        "example.cvl",
        "example.pipeline"
      ]
    ]
  end

  defp check_nsai_versions(_) do
    Mix.Task.run("app.start", ["--no-start"])

    case MedlumLlm.Integration.VersionCheck.check_all() do
      :ok -> Mix.shell().info("All NSAI libraries loaded successfully")
      {:error, errors} -> Mix.shell().error("Missing libraries: #{inspect(errors)}")
    end
  end
end
