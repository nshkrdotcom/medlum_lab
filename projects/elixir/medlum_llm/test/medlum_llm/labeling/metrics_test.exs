defmodule MedlumLlm.Labeling.MetricsTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Labeling.Metrics

  describe "cvl_metric_keys/0" do
    test "returns all CVL-specific metric keys" do
      keys = Metrics.cvl_metric_keys()

      assert :cvl_accuracy in keys
      assert :hallucination_precision in keys
      assert :hallucination_recall in keys
      assert :hallucination_f1 in keys
      assert :medication_accuracy in keys
      assert :diagnosis_accuracy in keys
      assert :lab_accuracy in keys
      assert :temporal_accuracy in keys
    end
  end

  describe "statistical_keys/0" do
    test "returns all statistical metric keys" do
      keys = Metrics.statistical_keys()

      assert :confidence_interval_lower in keys
      assert :confidence_interval_upper in keys
      assert :sample_size in keys
      assert :p_value in keys
      assert :standard_error in keys
      assert :cohens_kappa in keys
      assert :fleiss_kappa in keys
    end
  end

  describe "latency_keys/0" do
    test "returns all latency metric keys" do
      keys = Metrics.latency_keys()

      assert :latency_p50_ms in keys
      assert :latency_p95_ms in keys
      assert :latency_p99_ms in keys
      assert :latency_mean_ms in keys
    end
  end

  describe "standard_ml_keys/0" do
    test "returns all standard ML metric keys" do
      keys = Metrics.standard_ml_keys()

      assert :accuracy in keys
      assert :precision in keys
      assert :recall in keys
      assert :f1 in keys
      assert :f1_macro in keys
      assert :f1_micro in keys
      assert :auc_roc in keys
      assert :auc_pr in keys
    end
  end

  describe "all_keys/0" do
    test "returns all known metric keys" do
      all = Metrics.all_keys()

      # Should include CVL metrics
      assert :hallucination_f1 in all

      # Should include statistical keys
      assert :sample_size in all

      # Should include latency keys
      assert :latency_p95_ms in all

      # Should include standard ML keys
      assert :accuracy in all
    end

    test "is union of all category lists" do
      all = Metrics.all_keys()

      expected =
        Metrics.cvl_metric_keys() ++
          Metrics.statistical_keys() ++
          Metrics.latency_keys() ++
          Metrics.standard_ml_keys()

      assert MapSet.new(all) == MapSet.new(expected)
    end
  end

  describe "valid_cvl_metric?/1" do
    test "returns true for CVL metrics" do
      assert Metrics.valid_cvl_metric?(:hallucination_recall)
      assert Metrics.valid_cvl_metric?(:medication_accuracy)
    end

    test "returns false for non-CVL metrics" do
      refute Metrics.valid_cvl_metric?(:accuracy)
      refute Metrics.valid_cvl_metric?(:sample_size)
    end

    test "returns false for unknown metrics" do
      refute Metrics.valid_cvl_metric?(:unknown_metric)
    end

    test "returns false for non-atom input" do
      refute Metrics.valid_cvl_metric?("hallucination_f1")
    end
  end

  describe "valid_statistical_key?/1" do
    test "returns true for statistical keys" do
      assert Metrics.valid_statistical_key?(:sample_size)
      assert Metrics.valid_statistical_key?(:p_value)
    end

    test "returns false for non-statistical keys" do
      refute Metrics.valid_statistical_key?(:accuracy)
      refute Metrics.valid_statistical_key?(:hallucination_f1)
    end
  end

  describe "valid_metric_key?/1" do
    test "returns true for any known metric" do
      assert Metrics.valid_metric_key?(:hallucination_f1)
      assert Metrics.valid_metric_key?(:sample_size)
      assert Metrics.valid_metric_key?(:latency_p95_ms)
      assert Metrics.valid_metric_key?(:accuracy)
    end

    test "returns false for unknown metrics" do
      refute Metrics.valid_metric_key?(:unknown_metric)
      refute Metrics.valid_metric_key?(:custom_metric)
    end

    test "returns false for non-atom input" do
      refute Metrics.valid_metric_key?("accuracy")
      refute Metrics.valid_metric_key?(nil)
    end
  end

  describe "metric_key_to_string/1" do
    test "converts atom to string" do
      assert Metrics.metric_key_to_string(:hallucination_precision) == "hallucination_precision"
      assert Metrics.metric_key_to_string(:sample_size) == "sample_size"
    end
  end

  describe "string_to_metric_key/1" do
    test "parses known metric strings" do
      assert {:ok, :hallucination_f1} = Metrics.string_to_metric_key("hallucination_f1")
      assert {:ok, :sample_size} = Metrics.string_to_metric_key("sample_size")
      assert {:ok, :accuracy} = Metrics.string_to_metric_key("accuracy")
    end

    test "returns error for unknown metric strings" do
      assert {:error, :unknown_metric} = Metrics.string_to_metric_key("unknown_metric")
    end

    test "returns error for non-string input" do
      assert {:error, :unknown_metric} = Metrics.string_to_metric_key(:atom)
      assert {:error, :unknown_metric} = Metrics.string_to_metric_key(nil)
    end
  end

  describe "cvl_metrics_template/0" do
    test "returns map with all CVL metrics as nil" do
      template = Metrics.cvl_metrics_template()

      assert is_map(template)
      assert Map.has_key?(template, "cvl_accuracy")
      assert Map.has_key?(template, "hallucination_f1")
      assert template["cvl_accuracy"] == nil
    end

    test "uses string keys" do
      template = Metrics.cvl_metrics_template()

      for {key, _value} <- template do
        assert is_binary(key)
      end
    end
  end

  describe "statistical_template/0" do
    test "returns map with all statistical keys as nil" do
      template = Metrics.statistical_template()

      assert is_map(template)
      assert Map.has_key?(template, "sample_size")
      assert Map.has_key?(template, "p_value")
      assert template["sample_size"] == nil
    end
  end

  describe "validate_metric_keys/1" do
    test "returns ok for valid metric keys" do
      metrics = %{
        "accuracy" => 0.85,
        "hallucination_f1" => 0.90,
        "sample_size" => 1000
      }

      assert {:ok, ^metrics} = Metrics.validate_metric_keys(metrics)
    end

    test "returns error for unknown keys" do
      metrics = %{
        "accuracy" => 0.85,
        "unknown_metric" => 0.5,
        "another_unknown" => 0.3
      }

      assert {:error, {:unknown_keys, unknown}} = Metrics.validate_metric_keys(metrics)
      assert "unknown_metric" in unknown
      assert "another_unknown" in unknown
    end

    test "ignores non-string keys" do
      metrics = %{
        "accuracy" => 0.85,
        :atom_key => 0.5
      }

      # Non-string keys are ignored in validation
      assert {:ok, _} = Metrics.validate_metric_keys(metrics)
    end

    test "returns error for non-map input" do
      assert {:error, :not_a_map} = Metrics.validate_metric_keys("not a map")
    end
  end
end
