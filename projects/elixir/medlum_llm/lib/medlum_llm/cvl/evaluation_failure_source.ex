defmodule MedlumLlm.CVL.EvaluationFailureSource do
  @moduledoc """
  Forge Source implementation for reading evaluation failures from JSON files.

  This source reads evaluation results from `priv/eval_results/*.json` files,
  filters by error type, and transforms them into `Forge.Sample` structs for
  the CVL training pipeline.

  ## Configuration Options

  - `:results_dir` - Directory containing JSON result files (required)
  - `:filters` - List of error types to include (default: `[:error, :incorrect, :low_confidence]`)
  - `:min_confidence` - Minimum confidence threshold for low_confidence filtering (default: `0.5`)

  ## Error Types

  - `:error` - Sample processing failed (timeout, crash, etc.)
  - `:incorrect` - Model prediction was wrong
  - `:low_confidence` - Model confidence below threshold
  - `:contradiction` - CVL detected contradiction

  ## JSON Schema Expected

  ```json
  {
    "run": {
      "id": "run_id",
      "benchmark": "medqa_zero_shot",
      "status": "completed"
    },
    "errors": [
      {
        "sample_idx": 0,
        "sample_id": "medqa_0001",
        "error": "incorrect",
        "model": "openbio_8b",
        "context": "...",
        "model_output": "...",
        "expected": "A",
        "predicted": "B"
      }
    ]
  }
  ```

  ## Example

      iex> {:ok, state} = EvaluationFailureSource.init(results_dir: "priv/eval_results")
      iex> {:ok, sample, new_state} = EvaluationFailureSource.fetch(state)
      iex> sample.data.error_type
      :incorrect
  """

  @behaviour Forge.Source

  require Logger

  @type error_type :: :error | :incorrect | :low_confidence | :contradiction

  @type state :: %{
          results_dir: String.t(),
          filters: [error_type()],
          min_confidence: float(),
          files: [String.t()] | nil,
          current_file: %{samples: [Forge.Sample.t()]} | nil
        }

  @impl true
  @spec init(keyword()) :: {:ok, state()} | {:error, term()}
  def init(opts) do
    results_dir = Keyword.fetch!(opts, :results_dir)
    filters = Keyword.get(opts, :filters, [:error, :incorrect, :low_confidence])
    min_confidence = Keyword.get(opts, :min_confidence, 0.5)

    # Validate results directory exists
    unless File.exists?(results_dir) do
      Logger.warning("Results directory does not exist: #{results_dir}")
    end

    state = %{
      results_dir: results_dir,
      filters: filters,
      min_confidence: min_confidence,
      files: nil,
      current_file: nil
    }

    {:ok, state}
  end

  @impl true
  @spec fetch(state()) :: {:ok, [map()], state()} | {:done, state()}
  def fetch(state) do
    state = ensure_files_loaded(state)

    case get_next_batch(state) do
      {:ok, samples, new_state} ->
        # Return sample data as maps (not Forge.Sample structs)
        # The pipeline will convert these to Forge.Sample
        sample_maps = Enum.map(samples, fn sample ->
          Map.merge(sample.data, %{
            id: sample.id,
            pipeline: sample.pipeline,
            status: sample.status,
            created_at: sample.created_at
          })
        end)
        {:ok, sample_maps, new_state}

      :done ->
        {:done, state}
    end
  end

  # Fetches a batch of samples (up to batch_size at a time)
  @batch_size 50

  @spec get_next_batch(state()) :: {:ok, [Forge.Sample.t()], state()} | :done
  defp get_next_batch(state) do
    get_next_batch(state, [], @batch_size)
  end

  defp get_next_batch(state, acc, 0) do
    if acc == [] do
      :done
    else
      {:ok, Enum.reverse(acc), state}
    end
  end

  defp get_next_batch(state, acc, remaining) do
    case get_next_sample(state) do
      {:ok, sample, new_state} ->
        get_next_batch(new_state, [sample | acc], remaining - 1)

      :done ->
        if acc == [] do
          :done
        else
          {:ok, Enum.reverse(acc), state}
        end
    end
  end

  @impl true
  @spec cleanup(state()) :: :ok
  def cleanup(_state) do
    :ok
  end

  # Private functions

  @spec ensure_files_loaded(state()) :: state()
  defp ensure_files_loaded(%{files: nil, results_dir: dir} = state) do
    files =
      Path.wildcard(Path.join(dir, "*.json"))
      |> Enum.sort()

    Logger.debug("Found #{length(files)} evaluation result files in #{dir}")
    %{state | files: files}
  end

  defp ensure_files_loaded(state), do: state

  @spec get_next_sample(state()) :: {:ok, Forge.Sample.t(), state()} | :done
  defp get_next_sample(%{files: [], current_file: nil} = _state), do: :done

  defp get_next_sample(%{files: [file | rest], current_file: nil} = state) do
    case load_file(file, state) do
      {:ok, samples} when samples != [] ->
        [sample | remaining] = samples
        new_state = %{state | files: rest, current_file: %{samples: remaining}}
        {:ok, sample, new_state}

      {:ok, []} ->
        # No matching samples in this file, try next
        get_next_sample(%{state | files: rest})

      {:error, reason} ->
        Logger.warning("Failed to load file #{file}: #{inspect(reason)}")
        get_next_sample(%{state | files: rest})
    end
  end

  defp get_next_sample(%{current_file: %{samples: [sample | rest]}} = state) do
    {:ok, sample, %{state | current_file: %{samples: rest}}}
  end

  defp get_next_sample(%{current_file: %{samples: []}} = state) do
    get_next_sample(%{state | current_file: nil})
  end

  @spec load_file(String.t(), state()) :: {:ok, [Forge.Sample.t()]} | {:error, term()}
  defp load_file(path, state) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      samples = transform_to_samples(data, state)
      {:ok, samples}
    end
  end

  @spec transform_to_samples(map(), state()) :: [Forge.Sample.t()]
  defp transform_to_samples(%{"errors" => errors, "run" => run}, state) when is_list(errors) do
    errors
    |> Enum.filter(&filter_error(&1, state))
    |> Enum.map(&build_sample(&1, run))
  end

  defp transform_to_samples(%{"errors" => errors} = data, state) when is_list(errors) do
    # Handle case where "run" key might be missing
    run = Map.get(data, "run", %{"id" => "unknown", "benchmark" => "unknown"})
    transform_to_samples(%{"errors" => errors, "run" => run}, state)
  end

  defp transform_to_samples(_data, _state), do: []

  @spec filter_error(map(), state()) :: boolean()
  defp filter_error(error, %{filters: filters, min_confidence: min_confidence}) do
    error_type = parse_error_type(error["error"])

    cond do
      error_type not in filters ->
        false

      error_type == :low_confidence ->
        # For low_confidence errors, also check the confidence threshold
        confidence = error["confidence"] || 1.0
        confidence < min_confidence

      true ->
        true
    end
  end

  @spec parse_error_type(String.t() | atom() | nil) :: error_type()
  defp parse_error_type(error) when is_binary(error) do
    case String.downcase(error) do
      "error" -> :error
      "incorrect" -> :incorrect
      "low_confidence" -> :low_confidence
      "contradiction" -> :contradiction
      "timeout" -> :error
      "crash" -> :error
      _ -> :error
    end
  end

  defp parse_error_type(error) when is_atom(error), do: error
  defp parse_error_type(_), do: :error

  @spec build_sample(map(), map()) :: Forge.Sample.t()
  defp build_sample(error, run) do
    sample_id = generate_sample_id(run, error)

    %Forge.Sample{
      id: sample_id,
      pipeline: :cvl_training,
      data: %{
        source_document: error["context"] || error["source_document"],
        generated_summary: error["model_output"] || error["generated_summary"],
        gold_answer: error["expected"] || error["gold_answer"],
        predicted_answer: error["predicted"] || error["predicted_answer"],
        error_type: parse_error_type(error["error"]),
        model: parse_model(error["model"]),
        benchmark: parse_benchmark(run["benchmark"]),
        eval_run_id: run["id"],
        sample_idx: error["sample_idx"],
        original_sample_id: error["sample_id"],
        question: error["question"],
        options: error["options"]
      },
      measurements: %{},
      status: :pending,
      created_at: DateTime.utc_now()
    }
  end

  @spec generate_sample_id(map(), map()) :: String.t()
  defp generate_sample_id(run, error) do
    benchmark = run["benchmark"] || "unknown"
    model = error["model"] || "unknown"
    idx = error["sample_idx"] || System.unique_integer([:positive])

    "cvl_#{benchmark}_#{model}_#{idx}"
  end

  @spec parse_model(String.t() | atom() | nil) :: atom()
  defp parse_model(model) when is_binary(model) do
    model
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.to_atom()
  end

  defp parse_model(model) when is_atom(model), do: model
  defp parse_model(_), do: :unknown

  @spec parse_benchmark(String.t() | atom() | nil) :: atom()
  defp parse_benchmark(benchmark) when is_binary(benchmark) do
    benchmark
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.to_atom()
  end

  defp parse_benchmark(benchmark) when is_atom(benchmark), do: benchmark
  defp parse_benchmark(_), do: :unknown
end
