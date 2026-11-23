defmodule MedlumLlm.Eval.Experiments do
  @moduledoc """
  Helpers for defining medical evaluation experiments.

  Provides convenience functions for setting up crucible_harness experiments
  with medical benchmarks.

  ## Usage

      # Create experiment configuration from a benchmark
      config = MedlumLlm.Eval.Experiments.from_benchmark(:medqa_zero_shot)

      # Create with custom options
      config = MedlumLlm.Eval.Experiments.from_benchmark(:medqa_zero_shot,
        models: [:biomistral_7b, :openbio_8b],
        limit: 100
      )
  """

  alias MedlumLlm.Datasets
  alias MedlumLlm.Chat
  alias MedlumLlm.Eval.{Benchmarks, Prompts, MedicalMetrics, Baselines}

  @doc """
  Create experiment configuration from a benchmark.

  Returns a map suitable for use with crucible_harness.

  ## Options

  - `:models` - Override default models for the benchmark
  - `:limit` - Limit number of samples (for development)
  - `:seed` - Random seed for sampling (default: 42)

  ## Examples

      config = MedlumLlm.Eval.Experiments.from_benchmark(:medqa_zero_shot)

      config = MedlumLlm.Eval.Experiments.from_benchmark(:medqa_zero_shot,
        models: [:biomistral_7b],
        limit: 50
      )

  """
  @spec from_benchmark(atom(), keyword()) :: map()
  def from_benchmark(benchmark_name, opts \\ []) do
    {:ok, config} = Benchmarks.get(benchmark_name)

    models = Keyword.get(opts, :models, config.default_models)
    limit = Keyword.get(opts, :limit)
    seed = Keyword.get(opts, :seed, 42)

    %{
      name: config.name,
      description: config.description,
      benchmark: benchmark_name,

      dataset_fn: fn ->
        dataset_opts = [split: config.split, seed: seed]
        dataset_opts = if limit, do: Keyword.put(dataset_opts, :limit, limit), else: dataset_opts
        {:ok, ds} = Datasets.load(config.dataset, dataset_opts)
        ds
      end,

      conditions: Enum.map(models, fn model ->
        %{id: model, model: model}
      end),

      metrics: config.metrics,

      run_fn: fn condition, sample, _ctx ->
        run_sample(config, condition, sample)
      end,

      analyze_fn: fn results, _ctx ->
        analyze_results(config, results)
      end
    }
  end

  @doc """
  Run evaluation on a single sample.

  ## Options

  - `:model` - Model atom to use for inference
  - `:timeout` - Timeout in milliseconds

  ## Examples

      sample = %{question: "What is...", options: [...], answer: "A"}
      result = MedlumLlm.Eval.Experiments.run_sample(config, %{model: :biomistral_7b}, sample)

  """
  @spec run_sample(map(), map(), map()) :: map()
  def run_sample(config, condition, sample) do
    prompt = Prompts.format(config.prompt_template, sample)
    timeout = config[:timeout_ms] || 60_000

    start_time = System.monotonic_time(:millisecond)
    result = Chat.chat(prompt, model: condition.model, timeout: timeout)
    latency = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, response} ->
        predicted = parse_response(config.task, response)
        expected = sample[:answer] || sample["answer"]
        correct = predicted == expected

        %{
          predicted: predicted,
          expected: expected,
          correct: correct,
          latency_ms: latency,
          response: response
        }

      {:error, reason} ->
        %{
          predicted: nil,
          expected: sample[:answer] || sample["answer"],
          correct: false,
          latency_ms: latency,
          error: reason
        }
    end
  end

  @doc """
  Analyze results from all conditions.

  ## Examples

      results = %{
        biomistral_7b: [%{correct: true, ...}, %{correct: false, ...}],
        openbio_8b: [%{correct: true, ...}, %{correct: true, ...}]
      }

      analysis = MedlumLlm.Eval.Experiments.analyze_results(config, results)

  """
  @spec analyze_results(map(), map()) :: [map()]
  def analyze_results(config, results) do
    for {condition_id, condition_results} <- results do
      _predictions = Enum.map(condition_results, & &1.predicted)
      samples = Enum.map(condition_results, fn r ->
        %{answer: r.expected}
      end)

      n = length(samples)
      correct = Enum.count(condition_results, & &1.correct)
      accuracy = if n > 0, do: correct / n, else: 0.0

      latencies = Enum.map(condition_results, & &1.latency_ms)

      %{
        condition: condition_id,
        accuracy: accuracy,
        accuracy_pct: "#{Float.round(accuracy * 100, 1)}%",
        ci_95: MedicalMetrics.wilson_ci(correct, n),
        baseline_comparison: Baselines.format_comparison(config.dataset, condition_id, accuracy),
        baseline_status: Baselines.compare(config.dataset, condition_id, accuracy),
        sample_count: n,
        correct_count: correct,
        error_count: Enum.count(condition_results, & Map.has_key?(&1, :error)),
        latency_p50: percentile(latencies, 0.5),
        latency_p95: percentile(latencies, 0.95),
        latency_mean: mean(latencies)
      }
    end
  end

  @doc """
  Create a comparison table between conditions.

  ## Examples

      table = MedlumLlm.Eval.Experiments.comparison_table(analysis)

  """
  @spec comparison_table([map()]) :: [map()]
  def comparison_table(analysis) do
    analysis
    |> Enum.map(fn result ->
      %{
        model: result.condition,
        accuracy: result.accuracy_pct,
        ci_95: format_ci(result.ci_95),
        vs_baseline: result.baseline_comparison,
        status: result.baseline_status,
        p50_ms: round(result.latency_p50),
        p95_ms: round(result.latency_p95),
        n: result.sample_count
      }
    end)
    |> Enum.sort_by(& &1.accuracy, :desc)
  end

  @doc """
  Format experiment results as markdown.

  ## Examples

      md = MedlumLlm.Eval.Experiments.to_markdown(config, analysis)
      File.write!("results.md", md)

  """
  @spec to_markdown(map(), [map()]) :: String.t()
  def to_markdown(config, analysis) do
    table = comparison_table(analysis)

    header = """
    # #{config[:name] || "Evaluation Results"}

    #{config[:description] || ""}

    ## Results

    | Model | Accuracy | 95% CI | vs Baseline | Status | p50 (ms) | p95 (ms) | N |
    |-------|----------|--------|-------------|--------|----------|----------|---|
    """

    rows = Enum.map(table, fn row ->
      status_emoji = case row.status do
        :match -> "pass"
        :above -> "above"
        :below -> "below"
        :no_baseline -> "n/a"
      end

      "| #{row.model} | #{row.accuracy} | #{row.ci_95} | #{row.vs_baseline} | #{status_emoji} | #{row.p50_ms} | #{row.p95_ms} | #{row.n} |"
    end)
    |> Enum.join("\n")

    header <> rows <> "\n"
  end

  # =========================================================================
  # Private Helpers
  # =========================================================================

  defp parse_response(:mcq, response), do: Prompts.parse_mcq_response(response)
  defp parse_response(:mcq_cot, response), do: Prompts.parse_cot_response(response).answer
  defp parse_response(:binary_qa, response), do: Prompts.parse_binary_response(response)
  defp parse_response(_, response), do: response

  defp percentile([], _), do: 0.0
  defp percentile(data, p) do
    sorted = Enum.sort(data)
    k = round(p * (length(sorted) - 1))
    Enum.at(sorted, k, 0)
  end

  defp mean([]), do: 0.0
  defp mean(data), do: Enum.sum(data) / length(data)

  defp format_ci({low, high}) do
    "[#{Float.round(low * 100, 1)}%, #{Float.round(high * 100, 1)}%]"
  end
end
