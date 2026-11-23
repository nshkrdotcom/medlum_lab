defmodule MedlumLlm.Telemetry.Reports do
  @moduledoc """
  Grant-ready report generation from telemetry data.

  This module generates formatted reports from experiment data suitable for:
  - Reproducible clinical evaluation reports
  - Benchmark deliverables
  - Academic publications
  - Internal documentation

  ## Supported Formats

  - `:markdown` - Evaluation reports, README files
  - `:latex` - Academic papers, publications
  - `:html` - Web reports with styling
  - `:json` - Structured data for API responses

  ## Usage

  ```elixir
  alias MedlumLlm.Telemetry.Reports

  # Generate markdown report
  {:ok, md} = Reports.generate(experiment_id, :markdown,
    title: "Medical LLM Benchmark - Q2 Results",
    include_environment: true,
    include_baselines: true
  )

  # Generate comparison table
  {:ok, table} = Reports.comparison_table([exp1_id, exp2_id], :markdown,
    title: "Model Comparison"
  )

  # Generate baseline comparison
  {:ok, section} = Reports.baseline_comparison(experiment_id,
    baselines: ["GPT-4", "GPT-3.5"]
  )
  ```
  """

  alias CrucibleTelemetry.Experiment
  alias MedlumLlm.Telemetry.{Baselines, Metrics}

  @typedoc "Report output format"
  @type report_format :: :markdown | :latex | :html | :json

  @typedoc "Report generation options"
  @type report_options :: [
          title: String.t(),
          include_environment: boolean(),
          include_baselines: boolean(),
          confidence_level: float(),
          baselines: [String.t()],
          dataset: String.t()
        ]

  @doc """
  Generate a report from experiment data.

  Creates a formatted report including model metrics, optional environment
  information, and baseline comparisons.

  ## Parameters

  - `experiment_id` - Single experiment ID or list of IDs
  - `format` - Output format (`:markdown`, `:latex`, `:html`, `:json`)
  - `opts` - Report options:
    - `:title` - Report title
    - `:include_environment` - Include environment fingerprint (default: false)
    - `:include_baselines` - Include baseline comparisons (default: false)
    - `:confidence_level` - CI confidence level (default: 0.95)

  ## Returns

  - `{:ok, String.t()}` - Generated report content
  - `{:error, term()}` - Error if experiment not found or no data

  ## Examples

      {:ok, report} = Reports.generate("exp_123", :markdown,
        title: "MedQA Evaluation Results",
        include_environment: true
      )
  """
  @spec generate(String.t() | [String.t()], report_format(), report_options()) ::
          {:ok, String.t()} | {:error, term()}
  def generate(experiment_id, format, opts \\ [])

  def generate(experiment_id, format, opts) when is_binary(experiment_id) do
    generate([experiment_id], format, opts)
  end

  def generate(experiment_ids, format, opts) when is_list(experiment_ids) do
    # Collect experiment data
    confidence = opts[:confidence_level] || 0.95

    experiments_data =
      Enum.map(experiment_ids, fn id ->
        with {:ok, exp} <- Experiment.get(id),
             {:ok, model_metrics} <- Metrics.calculate_model_metrics(id, confidence_level: confidence) do
          {:ok, {exp, model_metrics}}
        end
      end)

    # Check for errors
    case Enum.find(experiments_data, &match?({:error, _}, &1)) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        experiments = Enum.map(experiments_data, fn {:ok, data} -> data end)

        case format do
          :markdown -> {:ok, generate_markdown(experiments, opts)}
          :latex -> {:ok, generate_latex(experiments, opts)}
          :html -> {:ok, generate_html(experiments, opts)}
          :json -> {:ok, generate_json(experiments, opts)}
          _ -> {:error, :unsupported_format}
        end
    end
  end

  @doc """
  Generate a comparison table for multiple experiments.

  Creates a side-by-side comparison of metrics from multiple experiments,
  useful for A/B testing and model comparison.

  ## Parameters

  - `experiment_ids` - List of experiment IDs to compare
  - `format` - Output format
  - `opts` - Report options (`:title`, `:confidence_level`)

  ## Returns

  - `{:ok, String.t()}` - Formatted comparison table
  - `{:error, term()}` - Error if experiments not found

  ## Examples

      {:ok, table} = Reports.comparison_table(
        ["exp_control", "exp_treatment"],
        :markdown,
        title: "A/B Test Results"
      )
  """
  @spec comparison_table([String.t()], report_format(), report_options()) ::
          {:ok, String.t()} | {:error, term()}
  def comparison_table(experiment_ids, format, opts \\ []) do
    # Collect all experiment data
    experiments_data =
      Enum.map(experiment_ids, fn id ->
        with {:ok, exp} <- Experiment.get(id),
             {:ok, model_metrics} <- Metrics.calculate_model_metrics(id) do
          {:ok, {exp, model_metrics}}
        end
      end)

    case Enum.find(experiments_data, &match?({:error, _}, &1)) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        experiments = Enum.map(experiments_data, fn {:ok, data} -> data end)

        case format do
          :markdown -> {:ok, comparison_table_markdown(experiments, opts)}
          :latex -> {:ok, comparison_table_latex(experiments, opts)}
          _ -> {:ok, comparison_table_markdown(experiments, opts)}
        end
    end
  end

  @doc """
  Generate baseline comparison section.

  Compares experiment results against published baselines for context.

  ## Parameters

  - `experiment_id` - Experiment ID to compare
  - `opts` - Options:
    - `:baselines` - List of baseline model names to compare against
    - `:dataset` - Dataset name for baseline lookup (e.g., "medqa")

  ## Returns

  - `{:ok, String.t()}` - Formatted baseline comparison section
  - `{:error, term()}` - Error if experiment not found

  ## Examples

      {:ok, section} = Reports.baseline_comparison("exp_123",
        baselines: ["GPT-4", "GPT-3.5"],
        dataset: "medqa"
      )
  """
  @spec baseline_comparison(String.t(), report_options()) ::
          {:ok, String.t()} | {:error, term()}
  def baseline_comparison(experiment_id, opts \\ []) do
    with {:ok, _exp} <- Experiment.get(experiment_id),
         {:ok, model_metrics} <- Metrics.calculate_model_metrics(experiment_id) do
      dataset = Keyword.get(opts, :dataset, "medqa")
      baseline_names = Keyword.get(opts, :baselines, [])

      baselines =
        if Enum.empty?(baseline_names) do
          Baselines.list_baselines(dataset)
        else
          baseline_names
          |> Enum.map(&Baselines.get_baseline(dataset, model: &1))
          |> Enum.filter(&match?({:ok, _}, &1))
          |> Enum.map(fn {:ok, b} -> b end)
        end

      {:ok, format_baseline_comparison(model_metrics, baselines, opts)}
    end
  end

  # Markdown generation

  defp generate_markdown(experiments, opts) do
    title = Keyword.get(opts, :title, "Evaluation Results")
    include_env = Keyword.get(opts, :include_environment, false)
    include_baselines = Keyword.get(opts, :include_baselines, false)

    sections = [
      "# #{title}\n",
      "Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}\n",
      "\n## Summary\n",
      model_metrics_table_markdown(experiments),
      if(include_env, do: environment_section_markdown(experiments), else: ""),
      if(include_baselines, do: baselines_section_markdown(experiments, opts), else: "")
    ]

    Enum.join(sections, "\n")
  end

  defp model_metrics_table_markdown(experiments) do
    rows =
      experiments
      |> Enum.flat_map(fn {exp, model_metrics} ->
        for {model, metrics} <- model_metrics do
          ci_str =
            if metrics.accuracy_ci_lower && metrics.accuracy_ci_upper do
              "[#{format_float(metrics.accuracy_ci_lower)}, #{format_float(metrics.accuracy_ci_upper)}]"
            else
              "-"
            end

          latency_str = if metrics.latency_p95, do: "#{round(metrics.latency_p95)}ms", else: "-"

          "| #{exp.name} | #{model} | #{format_float(metrics.accuracy)} | #{ci_str} | #{latency_str} | #{metrics.total_samples} |"
        end
      end)

    header = """
    | Experiment | Model | Accuracy | 95% CI | Latency P95 | Samples |
    |------------|-------|----------|--------|-------------|---------|
    """

    header <> Enum.join(rows, "\n")
  end

  defp environment_section_markdown(experiments) do
    case find_environment(experiments) do
      nil ->
        ""

      env ->
        """

        ## Environment

        #{format_environment_markdown(env)}
        """
    end
  end

  defp format_environment_markdown(env) when is_map(env) do
    Enum.map_join(env, "\n", fn {k, v} -> "- **#{humanize_key(k)}**: #{v}" end)
  end

  defp format_environment_markdown(_), do: "No environment data available"

  defp baselines_section_markdown(_experiments, opts) do
    dataset = Keyword.get(opts, :dataset, "medqa")
    baselines = Baselines.list_baselines(dataset)

    if Enum.empty?(baselines) do
      ""
    else
      rows =
        baselines
        |> Enum.map(fn b ->
          "| #{b.model} | #{format_float(b.accuracy)} | #{b.source} |"
        end)

      """

      ## Published Baselines (#{dataset})

      | Model | Accuracy | Source |
      |-------|----------|--------|
      #{Enum.join(rows, "\n")}
      """
    end
  end

  # LaTeX generation

  defp generate_latex(experiments, opts) do
    title = Keyword.get(opts, :title, "Evaluation Results")

    table_rows =
      experiments
      |> Enum.flat_map(fn {_exp, model_metrics} ->
        for {model, metrics} <- model_metrics do
          ci_str =
            if metrics.accuracy_ci_lower && metrics.accuracy_ci_upper do
              "[#{format_float(metrics.accuracy_ci_lower)}, #{format_float(metrics.accuracy_ci_upper)}]"
            else
              "-"
            end

          latency_str = if metrics.latency_p95, do: "#{round(metrics.latency_p95)}ms", else: "-"

          "#{model} & #{format_float(metrics.accuracy)} & #{ci_str} & #{latency_str} \\\\"
        end
      end)

    """
    \\begin{table}[h]
    \\centering
    \\caption{#{title}}
    \\begin{tabular}{lrrr}
    \\toprule
    Model & Accuracy & 95\\% CI & P95 Latency \\\\
    \\midrule
    #{Enum.join(table_rows, "\n")}
    \\bottomrule
    \\end{tabular}
    \\label{tab:eval_results}
    \\end{table}
    """
  end

  # HTML generation

  defp generate_html(experiments, opts) do
    title = Keyword.get(opts, :title, "Evaluation Results")

    table_rows =
      experiments
      |> Enum.flat_map(fn {exp, model_metrics} ->
        for {model, metrics} <- model_metrics do
          ci_str =
            if metrics.accuracy_ci_lower && metrics.accuracy_ci_upper do
              "[#{format_float(metrics.accuracy_ci_lower)}, #{format_float(metrics.accuracy_ci_upper)}]"
            else
              "-"
            end

          latency_str = if metrics.latency_p95, do: "#{round(metrics.latency_p95)}ms", else: "-"

          """
          <tr>
            <td>#{exp.name}</td>
            <td>#{model}</td>
            <td>#{format_float(metrics.accuracy)}</td>
            <td>#{ci_str}</td>
            <td>#{latency_str}</td>
            <td>#{metrics.total_samples}</td>
          </tr>
          """
        end
      end)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <title>#{title}</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 2rem; }
        table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
        th, td { border: 1px solid #ddd; padding: 0.75rem; text-align: left; }
        th { background-color: #f5f5f5; font-weight: 600; }
        tr:nth-child(even) { background-color: #fafafa; }
        h1 { color: #333; }
        .timestamp { color: #666; font-size: 0.9rem; }
      </style>
    </head>
    <body>
      <h1>#{title}</h1>
      <p class="timestamp">Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}</p>

      <h2>Summary</h2>
      <table>
        <thead>
          <tr>
            <th>Experiment</th>
            <th>Model</th>
            <th>Accuracy</th>
            <th>95% CI</th>
            <th>Latency P95</th>
            <th>Samples</th>
          </tr>
        </thead>
        <tbody>
          #{Enum.join(table_rows, "\n")}
        </tbody>
      </table>
    </body>
    </html>
    """
  end

  # JSON generation

  defp generate_json(experiments, opts) do
    title = Keyword.get(opts, :title, "Evaluation Results")

    data = %{
      title: title,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      experiments:
        Enum.map(experiments, fn {exp, model_metrics} ->
          %{
            id: exp.id,
            name: exp.name,
            hypothesis: exp.hypothesis,
            condition: exp.condition,
            started_at: exp.started_at && DateTime.to_iso8601(exp.started_at),
            stopped_at: exp.stopped_at && DateTime.to_iso8601(exp.stopped_at),
            metadata: exp.metadata,
            model_metrics:
              for {model, metrics} <- model_metrics, into: %{} do
                {model, metrics}
              end
          }
        end)
    }

    Jason.encode!(data, pretty: true)
  end

  # Comparison table helpers

  defp comparison_table_markdown(experiments, opts) do
    title = Keyword.get(opts, :title, "Experiment Comparison")

    rows =
      experiments
      |> Enum.flat_map(fn {exp, model_metrics} ->
        for {model, metrics} <- model_metrics do
          ci_str =
            if metrics.accuracy_ci_lower && metrics.accuracy_ci_upper do
              "[#{format_float(metrics.accuracy_ci_lower)}, #{format_float(metrics.accuracy_ci_upper)}]"
            else
              "-"
            end

          "| #{exp.name} | #{exp.condition} | #{model} | #{format_float(metrics.accuracy)} | #{ci_str} |"
        end
      end)

    """
    ## #{title}

    | Experiment | Condition | Model | Accuracy | 95% CI |
    |------------|-----------|-------|----------|--------|
    #{Enum.join(rows, "\n")}
    """
  end

  defp comparison_table_latex(experiments, opts) do
    title = Keyword.get(opts, :title, "Experiment Comparison")

    rows =
      experiments
      |> Enum.flat_map(fn {exp, model_metrics} ->
        for {model, metrics} <- model_metrics do
          ci_str =
            if metrics.accuracy_ci_lower && metrics.accuracy_ci_upper do
              "[#{format_float(metrics.accuracy_ci_lower)}, #{format_float(metrics.accuracy_ci_upper)}]"
            else
              "-"
            end

          "#{exp.name} & #{exp.condition} & #{model} & #{format_float(metrics.accuracy)} & #{ci_str} \\\\"
        end
      end)

    """
    \\begin{table}[h]
    \\centering
    \\caption{#{title}}
    \\begin{tabular}{llrrr}
    \\toprule
    Experiment & Condition & Model & Accuracy & 95\\% CI \\\\
    \\midrule
    #{Enum.join(rows, "\n")}
    \\bottomrule
    \\end{tabular}
    \\end{table}
    """
  end

  # Baseline comparison formatting

  defp format_baseline_comparison(model_metrics, baselines, _opts) do
    model_rows =
      for {model, metrics} <- model_metrics do
        "| #{model} | #{format_float(metrics.accuracy)} | (experiment) |"
      end

    baseline_rows =
      for b <- baselines do
        "| #{b.model} | #{format_float(b.accuracy)} | #{b.source} |"
      end

    """
    ## Baseline Comparison

    | Model | Accuracy | Source |
    |-------|----------|--------|
    #{Enum.join(model_rows ++ baseline_rows, "\n")}
    """
  end

  # Helpers

  defp format_float(nil), do: "-"
  defp format_float(f) when is_float(f), do: :erlang.float_to_binary(f, decimals: 3)
  defp format_float(i) when is_integer(i), do: Integer.to_string(i)

  defp find_environment(experiments) do
    experiments
    |> Enum.find_value(fn {exp, _} ->
      get_in(exp.metadata, [:environment])
    end)
  end

  defp humanize_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanize_key(key), do: to_string(key)
end
