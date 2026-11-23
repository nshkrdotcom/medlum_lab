defmodule ElixirBioClinicalbert.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_bio_clinicalbert,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {ElixirBioClinicalbert.Application, []}
    ]
  end

  defp deps do
    [
      {:ollixir, "~> 0.1.0"},
      {:hf_hub, "~> 0.1.3"},
      {:mox, "~> 1.1", only: :test}
    ]
  end
end
