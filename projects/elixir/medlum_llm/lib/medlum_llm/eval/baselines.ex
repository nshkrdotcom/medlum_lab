defmodule MedlumLlm.Eval.Baselines do
  @moduledoc """
  Published baseline results for medical benchmarks.

  Used to validate our evaluation reproduces published results within +/-5%.

  ## Sources

  - OpenAI GPT-4 Technical Report (2023-03)
  - Google Med-PaLM 2 Paper (2023-05)
  - Meta Llama 3 Report (2024-04)
  - OpenBioLLM HuggingFace Card (2024-06)
  - II-Medical HuggingFace Card (2024-12)
  - BioMistral Paper (2024-02)
  - Meditron Paper (2023-11)

  ## Usage

      # Get all baselines for a dataset
      baselines = MedlumLlm.Eval.Baselines.get(:medqa)

      # Get specific model baseline
      {:ok, baseline} = MedlumLlm.Eval.Baselines.get(:medqa, :gpt4)
      baseline.accuracy
      #=> 0.86

      # Compare your result against baseline
      result = MedlumLlm.Eval.Baselines.compare(:medqa, :biomistral_7b, 0.63)
      #=> :match
  """

  @baselines %{
    medqa: %{
      gpt4: %{accuracy: 0.86, source: "OpenAI GPT-4 Technical Report", date: "2023-03"},
      medpalm2: %{accuracy: 0.85, source: "Google Med-PaLM 2 Paper", date: "2023-05"},
      llama3_70b: %{accuracy: 0.73, source: "Meta Llama 3 Report", date: "2024-04"},
      openbio_70b: %{accuracy: 0.79, source: "OpenBioLLM HF Card", date: "2024-06"},
      openbio_8b: %{accuracy: 0.75, source: "OpenBioLLM HF Card", date: "2024-06"},
      ii_medical_8b: %{accuracy: 0.88, source: "II-Medical HF Card", date: "2024-12"},
      biomistral_7b: %{accuracy: 0.61, source: "BioMistral Paper", date: "2024-02"},
      meditron_7b: %{accuracy: 0.63, source: "Meditron Paper", date: "2023-11"},
      meditron_70b: %{accuracy: 0.70, source: "Meditron Paper", date: "2023-11"}
    },

    pubmedqa: %{
      gpt4: %{accuracy: 0.75, source: "PubMedQA Leaderboard", date: "2024-01"},
      biomistral_7b: %{accuracy: 0.73, source: "BioMistral Paper", date: "2024-02"},
      ii_medical_8b: %{accuracy: 0.78, source: "II-Medical HF Card", date: "2024-12"}
    },

    medmcqa: %{
      gpt4: %{accuracy: 0.72, source: "MedMCQA Leaderboard", date: "2024-01"},
      ii_medical_8b: %{accuracy: 0.72, source: "II-Medical HF Card", date: "2024-12"},
      openbio_8b: %{accuracy: 0.65, source: "OpenBioLLM HF Card", date: "2024-06"}
    },

    mmlu_medical: %{
      gpt4: %{accuracy: 0.87, source: "MMLU Leaderboard", date: "2024-01"},
      llama3_70b: %{accuracy: 0.82, source: "Meta Llama 3 Report", date: "2024-04"},
      openbio_70b: %{accuracy: 0.78, source: "OpenBioLLM HF Card", date: "2024-06"}
    }
  }

  @doc """
  Get all baselines for a dataset.

  ## Examples

      baselines = MedlumLlm.Eval.Baselines.get(:medqa)
      Map.keys(baselines)
      #=> [:gpt4, :medpalm2, :llama3_70b, ...]

  """
  @spec get(atom()) :: map()
  def get(dataset) do
    Map.get(@baselines, dataset, %{})
  end

  @doc """
  Get baseline for a specific model on a dataset.

  ## Examples

      {:ok, baseline} = MedlumLlm.Eval.Baselines.get(:medqa, :gpt4)
      baseline.accuracy
      #=> 0.86
      baseline.source
      #=> "OpenAI GPT-4 Technical Report"

      {:error, :not_found} = MedlumLlm.Eval.Baselines.get(:medqa, :nonexistent)

  """
  @spec get(atom(), atom()) :: {:ok, map()} | {:error, :not_found}
  def get(dataset, model) do
    case Map.fetch(@baselines, dataset) do
      {:ok, dataset_baselines} ->
        case Map.fetch(dataset_baselines, model) do
          {:ok, baseline} -> {:ok, baseline}
          :error -> {:error, :not_found}
        end
      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Compare result against baseline.

  Returns:
  - `:match` - Within 5% of baseline
  - `:above` - More than 5% above baseline
  - `:below` - More than 5% below baseline
  - `:no_baseline` - No baseline available

  ## Examples

      MedlumLlm.Eval.Baselines.compare(:medqa, :biomistral_7b, 0.63)
      #=> :match

      MedlumLlm.Eval.Baselines.compare(:medqa, :biomistral_7b, 0.70)
      #=> :above

      MedlumLlm.Eval.Baselines.compare(:medqa, :biomistral_7b, 0.50)
      #=> :below

  """
  @spec compare(atom(), atom(), float()) :: :match | :above | :below | :no_baseline
  def compare(dataset, model, result_accuracy) do
    case get(dataset, model) do
      {:ok, baseline} ->
        diff = result_accuracy - baseline.accuracy
        cond do
          abs(diff) <= 0.05 -> :match
          diff > 0 -> :above
          true -> :below
        end
      {:error, _} ->
        :no_baseline
    end
  end

  @doc """
  Compare result against baseline with a custom tolerance.

  ## Examples

      # Check if within 2% of baseline
      MedlumLlm.Eval.Baselines.compare(:medqa, :gpt4, 0.85, tolerance: 0.02)
      #=> :match

  """
  @spec compare(atom(), atom(), float(), keyword()) :: :match | :above | :below | :no_baseline
  def compare(dataset, model, result_accuracy, opts) do
    tolerance = Keyword.get(opts, :tolerance, 0.05)

    case get(dataset, model) do
      {:ok, baseline} ->
        diff = result_accuracy - baseline.accuracy
        cond do
          abs(diff) <= tolerance -> :match
          diff > 0 -> :above
          true -> :below
        end
      {:error, _} ->
        :no_baseline
    end
  end

  @doc """
  Format comparison for reporting.

  ## Examples

      MedlumLlm.Eval.Baselines.format_comparison(:medqa, :biomistral_7b, 0.65)
      #=> "65.0% (+4.0% vs baseline 61.0%)"

      MedlumLlm.Eval.Baselines.format_comparison(:medqa, :unknown_model, 0.70)
      #=> "70.0% (no baseline)"

  """
  @spec format_comparison(atom(), atom(), float()) :: String.t()
  def format_comparison(dataset, model, result_accuracy) do
    case get(dataset, model) do
      {:ok, baseline} ->
        diff = result_accuracy - baseline.accuracy
        sign = if diff >= 0, do: "+", else: ""
        result_pct = Float.round(result_accuracy * 100, 1)
        diff_pct = Float.round(diff * 100, 1)
        baseline_pct = Float.round(baseline.accuracy * 100, 1)
        "#{result_pct}% (#{sign}#{diff_pct}% vs baseline #{baseline_pct}%)"
      {:error, _} ->
        "#{Float.round(result_accuracy * 100, 1)}% (no baseline)"
    end
  end

  @doc """
  List all datasets with baselines.

  ## Examples

      MedlumLlm.Eval.Baselines.datasets()
      #=> [:medqa, :pubmedqa, :medmcqa, :mmlu_medical]

  """
  @spec datasets() :: [atom()]
  def datasets, do: Map.keys(@baselines)

  @doc """
  List all models with baselines for a dataset.

  ## Examples

      MedlumLlm.Eval.Baselines.models(:medqa)
      #=> [:gpt4, :medpalm2, :llama3_70b, :openbio_70b, ...]

  """
  @spec models(atom()) :: [atom()]
  def models(dataset) do
    case Map.fetch(@baselines, dataset) do
      {:ok, baselines} -> Map.keys(baselines)
      :error -> []
    end
  end

  @doc """
  Get all baselines as a nested map.

  ## Examples

      all = MedlumLlm.Eval.Baselines.all()
      all.medqa.gpt4.accuracy
      #=> 0.86

  """
  @spec all() :: map()
  def all, do: @baselines

  @doc """
  Check if a baseline exists.

  ## Examples

      MedlumLlm.Eval.Baselines.exists?(:medqa, :gpt4)
      #=> true

      MedlumLlm.Eval.Baselines.exists?(:medqa, :unknown)
      #=> false

  """
  @spec exists?(atom(), atom()) :: boolean()
  def exists?(dataset, model) do
    case get(dataset, model) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get the accuracy for a model on a dataset.

  Returns nil if no baseline exists.

  ## Examples

      MedlumLlm.Eval.Baselines.accuracy(:medqa, :gpt4)
      #=> 0.86

      MedlumLlm.Eval.Baselines.accuracy(:medqa, :unknown)
      #=> nil

  """
  @spec accuracy(atom(), atom()) :: float() | nil
  def accuracy(dataset, model) do
    case get(dataset, model) do
      {:ok, baseline} -> baseline.accuracy
      {:error, _} -> nil
    end
  end

  @doc """
  Create a summary table of baselines for a dataset.

  Returns a list of maps suitable for rendering as a table.

  ## Examples

      MedlumLlm.Eval.Baselines.summary_table(:medqa)
      #=> [
        %{model: :gpt4, accuracy: 0.86, source: "OpenAI...", date: "2023-03"},
        %{model: :medpalm2, accuracy: 0.85, source: "Google...", date: "2023-05"},
        ...
      ]

  """
  @spec summary_table(atom()) :: [map()]
  def summary_table(dataset) do
    get(dataset)
    |> Enum.map(fn {model, baseline} ->
      %{
        model: model,
        accuracy: baseline.accuracy,
        accuracy_pct: "#{Float.round(baseline.accuracy * 100, 1)}%",
        source: baseline.source,
        date: baseline.date
      }
    end)
    |> Enum.sort_by(& &1.accuracy, :desc)
  end
end
