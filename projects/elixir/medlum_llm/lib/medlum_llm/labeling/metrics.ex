defmodule MedlumLlm.Labeling.Metrics do
  @moduledoc """
  Standard metric keys for medical evaluation.

  Provides constant definitions and validation for metric keys used in
  `LabelingIR.EvalRun.metrics` for CVL evaluation workflows.

  ## Metric Categories

  ### CVL-Specific Metrics
  - Hallucination detection metrics (precision, recall, F1)
  - Domain accuracy metrics (medication, diagnosis, lab)
  - Overall CVL accuracy

  ### Statistical Metrics
  - Confidence intervals
  - Sample sizes
  - P-values

  ## Example

      alias MedlumLlm.Labeling.Metrics

      # Get all CVL metric keys
      Metrics.cvl_metric_keys()
      # => [:cvl_accuracy, :hallucination_precision, ...]

      # Validate a metric key
      Metrics.valid_cvl_metric?(:hallucination_recall)
      # => true

      # Build a metrics map with CVL metrics
      metrics = %{
        "accuracy" => 0.85,
        "hallucination_precision" => 0.89,
        "hallucination_recall" => 0.92,
        "hallucination_f1" => 0.90,
        "medication_accuracy" => 0.91,
        "sample_size" => 1000
      }

  """

  @cvl_metrics [
    :cvl_accuracy,
    :hallucination_precision,
    :hallucination_recall,
    :hallucination_f1,
    :medication_accuracy,
    :diagnosis_accuracy,
    :lab_accuracy,
    :temporal_accuracy
  ]

  @statistical_keys [
    :confidence_interval_lower,
    :confidence_interval_upper,
    :sample_size,
    :p_value,
    :standard_error,
    :cohens_kappa,
    :fleiss_kappa
  ]

  @latency_keys [
    :latency_p50_ms,
    :latency_p95_ms,
    :latency_p99_ms,
    :latency_mean_ms
  ]

  @standard_ml_keys [
    :accuracy,
    :precision,
    :recall,
    :f1,
    :f1_macro,
    :f1_micro,
    :auc_roc,
    :auc_pr
  ]

  @doc """
  Returns the list of CVL-specific metric keys.

  These metrics are specific to Clinical Verification Layer evaluation:
  - `:cvl_accuracy` - Overall CVL system accuracy
  - `:hallucination_precision` - Precision of hallucination detection
  - `:hallucination_recall` - Recall of hallucination detection
  - `:hallucination_f1` - F1 score for hallucination detection
  - `:medication_accuracy` - Accuracy on medication-related claims
  - `:diagnosis_accuracy` - Accuracy on diagnosis-related claims
  - `:lab_accuracy` - Accuracy on lab value claims
  - `:temporal_accuracy` - Accuracy on temporal/timeline claims

  ## Examples

      iex> MedlumLlm.Labeling.Metrics.cvl_metric_keys()
      [:cvl_accuracy, :hallucination_precision, :hallucination_recall, :hallucination_f1, :medication_accuracy, :diagnosis_accuracy, :lab_accuracy, :temporal_accuracy]

  """
  @spec cvl_metric_keys() :: [atom()]
  def cvl_metric_keys, do: @cvl_metrics

  @doc """
  Returns the list of statistical metric keys.

  These keys are used for statistical significance and reliability measures:
  - `:confidence_interval_lower` - Lower bound of confidence interval
  - `:confidence_interval_upper` - Upper bound of confidence interval
  - `:sample_size` - Number of samples in evaluation
  - `:p_value` - Statistical significance p-value
  - `:standard_error` - Standard error of the estimate
  - `:cohens_kappa` - Cohen's kappa for inter-rater agreement
  - `:fleiss_kappa` - Fleiss' kappa for multi-rater agreement

  ## Examples

      iex> MedlumLlm.Labeling.Metrics.statistical_keys()
      [:confidence_interval_lower, :confidence_interval_upper, :sample_size, :p_value, :standard_error, :cohens_kappa, :fleiss_kappa]

  """
  @spec statistical_keys() :: [atom()]
  def statistical_keys, do: @statistical_keys

  @doc """
  Returns the list of latency metric keys.

  These keys are used for performance/latency measurements:
  - `:latency_p50_ms` - 50th percentile latency in milliseconds
  - `:latency_p95_ms` - 95th percentile latency in milliseconds
  - `:latency_p99_ms` - 99th percentile latency in milliseconds
  - `:latency_mean_ms` - Mean latency in milliseconds

  ## Examples

      iex> MedlumLlm.Labeling.Metrics.latency_keys()
      [:latency_p50_ms, :latency_p95_ms, :latency_p99_ms, :latency_mean_ms]

  """
  @spec latency_keys() :: [atom()]
  def latency_keys, do: @latency_keys

  @doc """
  Returns the list of standard ML metric keys.

  Common machine learning evaluation metrics:
  - `:accuracy` - Overall classification accuracy
  - `:precision` - Precision (positive predictive value)
  - `:recall` - Recall (sensitivity)
  - `:f1` - F1 score (harmonic mean of precision and recall)
  - `:f1_macro` - Macro-averaged F1
  - `:f1_micro` - Micro-averaged F1
  - `:auc_roc` - Area under ROC curve
  - `:auc_pr` - Area under precision-recall curve

  ## Examples

      iex> MedlumLlm.Labeling.Metrics.standard_ml_keys()
      [:accuracy, :precision, :recall, :f1, :f1_macro, :f1_micro, :auc_roc, :auc_pr]

  """
  @spec standard_ml_keys() :: [atom()]
  def standard_ml_keys, do: @standard_ml_keys

  @doc """
  Returns all known metric keys.

  ## Examples

      iex> keys = MedlumLlm.Labeling.Metrics.all_keys()
      iex> :hallucination_f1 in keys
      true
      iex> :sample_size in keys
      true

  """
  @spec all_keys() :: [atom()]
  def all_keys do
    @cvl_metrics ++ @statistical_keys ++ @latency_keys ++ @standard_ml_keys
  end

  @doc """
  Checks if an atom is a valid CVL metric key.

  ## Examples

      iex> MedlumLlm.Labeling.Metrics.valid_cvl_metric?(:hallucination_recall)
      true

      iex> MedlumLlm.Labeling.Metrics.valid_cvl_metric?(:accuracy)
      false

      iex> MedlumLlm.Labeling.Metrics.valid_cvl_metric?(:unknown)
      false

  """
  @spec valid_cvl_metric?(atom()) :: boolean()
  def valid_cvl_metric?(key) when is_atom(key), do: key in @cvl_metrics
  def valid_cvl_metric?(_), do: false

  @doc """
  Checks if an atom is a valid statistical metric key.

  ## Examples

      iex> MedlumLlm.Labeling.Metrics.valid_statistical_key?(:sample_size)
      true

      iex> MedlumLlm.Labeling.Metrics.valid_statistical_key?(:accuracy)
      false

  """
  @spec valid_statistical_key?(atom()) :: boolean()
  def valid_statistical_key?(key) when is_atom(key), do: key in @statistical_keys
  def valid_statistical_key?(_), do: false

  @doc """
  Checks if an atom is any known metric key.

  ## Examples

      iex> MedlumLlm.Labeling.Metrics.valid_metric_key?(:hallucination_f1)
      true

      iex> MedlumLlm.Labeling.Metrics.valid_metric_key?(:latency_p95_ms)
      true

      iex> MedlumLlm.Labeling.Metrics.valid_metric_key?(:unknown_metric)
      false

  """
  @spec valid_metric_key?(atom()) :: boolean()
  def valid_metric_key?(key) when is_atom(key), do: key in all_keys()
  def valid_metric_key?(_), do: false

  @doc """
  Converts a metric key atom to its string representation.

  ## Examples

      iex> MedlumLlm.Labeling.Metrics.metric_key_to_string(:hallucination_precision)
      "hallucination_precision"

  """
  @spec metric_key_to_string(atom()) :: String.t()
  def metric_key_to_string(key) when is_atom(key), do: Atom.to_string(key)

  @doc """
  Converts a string to a known metric key atom.

  Returns `{:ok, atom}` for known keys, `{:error, :unknown_metric}` otherwise.

  ## Examples

      iex> MedlumLlm.Labeling.Metrics.string_to_metric_key("hallucination_f1")
      {:ok, :hallucination_f1}

      iex> MedlumLlm.Labeling.Metrics.string_to_metric_key("unknown_metric")
      {:error, :unknown_metric}

  """
  @spec string_to_metric_key(String.t()) :: {:ok, atom()} | {:error, :unknown_metric}
  def string_to_metric_key(str) when is_binary(str) do
    try do
      atom = String.to_existing_atom(str)
      if valid_metric_key?(atom), do: {:ok, atom}, else: {:error, :unknown_metric}
    rescue
      ArgumentError -> {:error, :unknown_metric}
    end
  end

  def string_to_metric_key(_), do: {:error, :unknown_metric}

  @doc """
  Returns a template metrics map with all CVL metrics initialized to nil.

  Useful for initializing an EvalRun metrics map.

  ## Examples

      iex> template = MedlumLlm.Labeling.Metrics.cvl_metrics_template()
      iex> Map.has_key?(template, "hallucination_f1")
      true
      iex> template["cvl_accuracy"]
      nil

  """
  @spec cvl_metrics_template() :: map()
  def cvl_metrics_template do
    Map.new(@cvl_metrics, fn key -> {Atom.to_string(key), nil} end)
  end

  @doc """
  Returns a template metrics map with all statistical keys initialized to nil.

  ## Examples

      iex> template = MedlumLlm.Labeling.Metrics.statistical_template()
      iex> Map.has_key?(template, "sample_size")
      true

  """
  @spec statistical_template() :: map()
  def statistical_template do
    Map.new(@statistical_keys, fn key -> {Atom.to_string(key), nil} end)
  end

  @doc """
  Validates that all keys in a metrics map are known metric keys.

  Returns `{:ok, metrics}` if all keys are valid, or `{:error, unknown_keys}`
  listing the unrecognized keys.

  ## Examples

      iex> metrics = %{"accuracy" => 0.85, "hallucination_f1" => 0.90}
      iex> MedlumLlm.Labeling.Metrics.validate_metric_keys(metrics)
      {:ok, %{"accuracy" => 0.85, "hallucination_f1" => 0.90}}

      iex> metrics = %{"accuracy" => 0.85, "unknown_metric" => 0.5}
      iex> MedlumLlm.Labeling.Metrics.validate_metric_keys(metrics)
      {:error, {:unknown_keys, ["unknown_metric"]}}

  """
  @spec validate_metric_keys(map()) :: {:ok, map()} | {:error, {:unknown_keys, [String.t()]}}
  def validate_metric_keys(metrics) when is_map(metrics) do
    all_key_strings = Enum.map(all_keys(), &Atom.to_string/1)

    unknown_keys =
      metrics
      |> Map.keys()
      |> Enum.filter(&is_binary/1)
      |> Enum.reject(&(&1 in all_key_strings))

    case unknown_keys do
      [] -> {:ok, metrics}
      keys -> {:error, {:unknown_keys, keys}}
    end
  end

  def validate_metric_keys(_), do: {:error, :not_a_map}
end
