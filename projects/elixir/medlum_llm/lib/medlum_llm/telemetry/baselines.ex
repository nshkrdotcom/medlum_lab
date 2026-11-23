defmodule MedlumLlm.Telemetry.Baselines do
  @moduledoc """
  Published baseline results for comparison.

  This module provides access to published baseline results from major LLM
  evaluations on medical benchmarks. Use these to contextualize your results
  against state-of-the-art performance.

  ## Pre-defined Baselines

  Includes published results from:
  - OpenAI (GPT-4, GPT-3.5)
  - Google (Med-PaLM 2, Gemini)
  - Open models (BioMistral, Meditron, etc.)

  ## Datasets

  - `medqa` - USMLE-style medical questions
  - `pubmedqa` - PubMed QA (pqa_labeled)
  - `medmcqa` - Medical MCQ from Indian exams

  ## Usage

  ```elixir
  alias MedlumLlm.Telemetry.Baselines

  # Get baseline for a specific model
  {:ok, baseline} = Baselines.get_baseline("medqa", model: "GPT-4")
  baseline.accuracy  # => 0.861

  # List all baselines for a dataset
  baselines = Baselines.list_baselines("medqa")

  # Register custom baseline
  Baselines.register_baseline(%{
    model: "MyModel",
    dataset: "medqa",
    accuracy: 0.75,
    source: "Internal Evaluation",
    year: 2026
  })
  ```

  ## Sources

  Baseline accuracy values are from published papers and official evaluations:
  - OpenAI technical reports
  - Google Research publications
  - Hugging Face leaderboards
  """

  use Agent

  @typedoc "Baseline result structure"
  @type baseline :: %{
          model: String.t(),
          dataset: String.t(),
          accuracy: float(),
          source: String.t(),
          year: non_neg_integer(),
          notes: String.t() | nil
        }

  # Pre-defined baselines from published results
  @medqa_baselines [
    %{
      model: "GPT-4",
      dataset: "medqa",
      accuracy: 0.861,
      source: "OpenAI 2023",
      year: 2023,
      notes: "5-shot, USMLE test set"
    },
    %{
      model: "GPT-3.5",
      dataset: "medqa",
      accuracy: 0.573,
      source: "OpenAI 2023",
      year: 2023,
      notes: "5-shot"
    },
    %{
      model: "Med-PaLM 2",
      dataset: "medqa",
      accuracy: 0.867,
      source: "Google 2023",
      year: 2023,
      notes: "5-shot ensemble"
    },
    %{
      model: "Med-PaLM",
      dataset: "medqa",
      accuracy: 0.674,
      source: "Google 2022",
      year: 2022,
      notes: "5-shot"
    },
    %{
      model: "Claude 3 Opus",
      dataset: "medqa",
      accuracy: 0.863,
      source: "Anthropic 2024",
      year: 2024,
      notes: "5-shot"
    },
    %{
      model: "Gemini 1.5 Pro",
      dataset: "medqa",
      accuracy: 0.875,
      source: "Google 2024",
      year: 2024,
      notes: "5-shot"
    },
    %{
      model: "BioMistral-7B",
      dataset: "medqa",
      accuracy: 0.612,
      source: "BioMistral 2024",
      year: 2024,
      notes: "Zero-shot, Q4_K_M quantized (NSAI internal)"
    },
    %{
      model: "Meditron-7B",
      dataset: "medqa",
      accuracy: 0.475,
      source: "EPFL 2023",
      year: 2023,
      notes: "Zero-shot"
    },
    %{
      model: "Meditron-70B",
      dataset: "medqa",
      accuracy: 0.701,
      source: "EPFL 2023",
      year: 2023,
      notes: "Zero-shot"
    }
  ]

  @pubmedqa_baselines [
    %{
      model: "GPT-4",
      dataset: "pubmedqa",
      accuracy: 0.75,
      source: "OpenAI 2023",
      year: 2023,
      notes: "pqa_labeled split"
    },
    %{
      model: "GPT-3.5",
      dataset: "pubmedqa",
      accuracy: 0.60,
      source: "OpenAI 2023",
      year: 2023,
      notes: "pqa_labeled split"
    },
    %{
      model: "Med-PaLM 2",
      dataset: "pubmedqa",
      accuracy: 0.812,
      source: "Google 2023",
      year: 2023,
      notes: "pqa_labeled split"
    },
    %{
      model: "BioGPT",
      dataset: "pubmedqa",
      accuracy: 0.817,
      source: "Microsoft 2022",
      year: 2022,
      notes: "Fine-tuned on PubMed"
    }
  ]

  @medmcqa_baselines [
    %{
      model: "GPT-4",
      dataset: "medmcqa",
      accuracy: 0.72,
      source: "OpenAI 2023",
      year: 2023,
      notes: "Test split"
    },
    %{
      model: "Med-PaLM 2",
      dataset: "medmcqa",
      accuracy: 0.724,
      source: "Google 2023",
      year: 2023,
      notes: "5-shot"
    },
    %{
      model: "Meditron-70B",
      dataset: "medmcqa",
      accuracy: 0.66,
      source: "EPFL 2023",
      year: 2023,
      notes: "Zero-shot"
    }
  ]

  @all_baselines %{
    "medqa" => @medqa_baselines,
    "pubmedqa" => @pubmedqa_baselines,
    "medmcqa" => @medmcqa_baselines
  }

  @doc """
  Start the baselines agent.

  Called automatically by the application supervisor. Initializes the
  agent with pre-defined baselines that can be extended at runtime.
  """
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> @all_baselines end, name: __MODULE__)
  end

  @doc """
  Get a baseline for a specific dataset and model.

  ## Parameters

  - `dataset` - Dataset name (e.g., "medqa", "pubmedqa")
  - `opts` - Filter options:
    - `:model` - Model name to match (partial match supported)
    - `:year` - Filter by publication year

  ## Returns

  - `{:ok, baseline()}` - Matching baseline
  - `{:error, :not_found}` - No matching baseline

  ## Examples

      {:ok, baseline} = Baselines.get_baseline("medqa", model: "GPT-4")
      baseline.accuracy  # => 0.861

      {:ok, baseline} = Baselines.get_baseline("medqa", model: "Med-PaLM", year: 2023)
  """
  @spec get_baseline(String.t(), keyword()) :: {:ok, baseline()} | {:error, :not_found}
  def get_baseline(dataset, opts \\ []) do
    model_filter = Keyword.get(opts, :model)
    year_filter = Keyword.get(opts, :year)

    baselines = get_baselines_for_dataset(dataset)

    result =
      baselines
      |> maybe_filter_by_model(model_filter)
      |> maybe_filter_by_year(year_filter)
      |> List.first()

    case result do
      nil -> {:error, :not_found}
      baseline -> {:ok, baseline}
    end
  end

  @doc """
  List all baselines for a dataset.

  ## Parameters

  - `dataset` - Dataset name (e.g., "medqa", "pubmedqa")

  ## Returns

  List of baseline structs, sorted by accuracy (descending).

  ## Examples

      baselines = Baselines.list_baselines("medqa")
      length(baselines)  # => 9 (or more if custom baselines added)
  """
  @spec list_baselines(String.t()) :: [baseline()]
  def list_baselines(dataset) do
    dataset
    |> get_baselines_for_dataset()
    |> Enum.sort_by(& &1.accuracy, :desc)
  end

  @doc """
  List all available datasets with baselines.

  ## Returns

  List of dataset name strings.

  ## Examples

      datasets = Baselines.list_datasets()
      # => ["medqa", "pubmedqa", "medmcqa"]
  """
  @spec list_datasets() :: [String.t()]
  def list_datasets do
    try do
      Agent.get(__MODULE__, &Map.keys/1)
    catch
      :exit, _ -> Map.keys(@all_baselines)
    end
  end

  @doc """
  Register a custom baseline.

  Adds a new baseline to the runtime store. This is useful for tracking
  internal evaluations or adding newly published results.

  ## Parameters

  - `baseline` - Baseline map with required keys:
    - `:model` - Model name
    - `:dataset` - Dataset name
    - `:accuracy` - Accuracy value (0.0-1.0)
    - `:source` - Citation or source
    - `:year` - Publication year

  ## Returns

  `:ok`

  ## Examples

      :ok = Baselines.register_baseline(%{
        model: "MyModel-7B",
        dataset: "medqa",
        accuracy: 0.72,
        source: "Internal Evaluation",
        year: 2026,
        notes: "Q4_K_M quantized"
      })
  """
  @spec register_baseline(baseline()) :: :ok
  def register_baseline(baseline) do
    validate_baseline!(baseline)

    dataset = baseline.dataset

    try do
      Agent.update(__MODULE__, fn state ->
        current = Map.get(state, dataset, [])
        Map.put(state, dataset, [baseline | current])
      end)
    catch
      :exit, _ ->
        # Agent not running, start it first
        {:ok, _} = start_link()
        register_baseline(baseline)
    end

    :ok
  end

  @doc """
  Clear all custom baselines, keeping only pre-defined ones.

  Useful for testing or resetting state.
  """
  @spec reset() :: :ok
  def reset do
    try do
      Agent.update(__MODULE__, fn _ -> @all_baselines end)
    catch
      :exit, _ -> :ok
    end

    :ok
  end

  # Private helpers

  defp get_baselines_for_dataset(dataset) do
    try do
      Agent.get(__MODULE__, fn state -> Map.get(state, dataset, []) end)
    catch
      :exit, _ ->
        # Agent not running, use defaults
        Map.get(@all_baselines, dataset, [])
    end
  end

  defp maybe_filter_by_model(baselines, nil), do: baselines

  defp maybe_filter_by_model(baselines, model_name) do
    model_lower = String.downcase(model_name)

    Enum.filter(baselines, fn b ->
      String.downcase(b.model) |> String.contains?(model_lower)
    end)
  end

  defp maybe_filter_by_year(baselines, nil), do: baselines

  defp maybe_filter_by_year(baselines, year) do
    Enum.filter(baselines, fn b -> b.year == year end)
  end

  defp validate_baseline!(baseline) do
    required_keys = [:model, :dataset, :accuracy, :source, :year]

    missing = Enum.filter(required_keys, fn k -> not Map.has_key?(baseline, k) end)

    if not Enum.empty?(missing) do
      raise ArgumentError, "Missing required baseline keys: #{inspect(missing)}"
    end

    if not is_float(baseline.accuracy) and not is_integer(baseline.accuracy) do
      raise ArgumentError, "Baseline accuracy must be a number"
    end

    if baseline.accuracy < 0 or baseline.accuracy > 1 do
      raise ArgumentError, "Baseline accuracy must be between 0 and 1"
    end

    :ok
  end
end
