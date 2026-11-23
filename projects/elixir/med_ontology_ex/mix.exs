defmodule MedOntology.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/medlum/med_ontology_ex"

  def project do
    [
      app: :med_ontology_ex,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex.pm package
      name: "MedOntology",
      description: "Unified medical ontology lookup service for SNOMED-CT, ICD-10, RxNorm, and LOINC",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,

      # Docs
      docs: docs(),

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MedOntology.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # HTTP client with connection pooling
      {:finch, "~> 0.18"},

      # JSON parsing
      {:jason, "~> 1.4"},

      # Telemetry for observability
      {:telemetry, "~> 1.2"},

      # Testing
      {:mox, "~> 1.0", only: :test},

      # Documentation
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},

      # Static analysis
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      name: "med_ontology_ex",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["MedLum Team"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "MedOntology",
      source_ref: "v#{@version}",
      canonical: "https://hexdocs.pm/med_ontology_ex",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        "Core Types": [
          MedOntology.Concept,
          MedOntology.Relationship,
          MedOntology.Mapping,
          MedOntology.SearchResult
        ],
        Ontologies: [
          MedOntology.SnomedCT,
          MedOntology.ICD10,
          MedOntology.RxNorm,
          MedOntology.LOINC
        ],
        Cache: [
          MedOntology.Cache.Server,
          MedOntology.Cache.Warmer,
          MedOntology.Cache.Sync
        ],
        Clients: [
          MedOntology.Client,
          MedOntology.Client.Snowstorm,
          MedOntology.Client.RxNav,
          MedOntology.Client.WHO,
          MedOntology.Client.LOINC
        ]
      ]
    ]
  end
end
