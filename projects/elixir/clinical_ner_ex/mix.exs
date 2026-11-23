defmodule ClinicalNerEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/medlum/clinical_ner_ex"

  def project do
    [
      app: :clinical_ner_ex,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      docs: docs(),
      name: "ClinicalNerEx",
      description: "Clinical Named Entity Recognition for medical text",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ClinicalNerEx.Application, []}
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},

      # Med ontology integration (will be available)
      # {:med_ontology_ex, "~> 0.1.0"},

      # ML dependencies (for transformer method - optional)
      # {:bumblebee, "~> 0.6", optional: true},
      # {:nx, "~> 0.9", optional: true},
      # {:exla, "~> 0.9", optional: true},

      # Testing
      {:mox, "~> 1.0", only: :test},
      {:stream_data, "~> 1.0", only: :test},

      # Development
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      test: ["test --trace"],
      quality: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "ClinicalNerEx",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
