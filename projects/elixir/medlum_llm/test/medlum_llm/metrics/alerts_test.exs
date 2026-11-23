defmodule MedlumLlm.Metrics.AlertsTest do
  use ExUnit.Case, async: false

  alias MedlumLlm.Metrics.Alerts

  setup do
    # Ensure Alerting GenServer is running for tests
    case Process.whereis(MetricsEx.Alerting) do
      nil ->
        {:ok, _pid} = MetricsEx.Alerting.start_link([])

      _pid ->
        :ok
    end

    # Remove any alerts from previous tests
    Alerts.remove_all()
    :ok
  end

  describe "define_standard_alerts/0" do
    test "defines all standard alert rules" do
      :ok = Alerts.define_standard_alerts()

      # Check that rules were defined by trying to get alerts
      # (The alerting module maintains state)
      alert_names = Alerts.alert_names()

      assert :low_accuracy in alert_names
      assert :cvl_critical_failure in alert_names
      assert :cvl_low_recall in alert_names
      assert :high_latency in alert_names
      assert :high_error_rate in alert_names
      assert :low_consensus in alert_names
    end

    test "returns :ok" do
      result = Alerts.define_standard_alerts()
      assert result == :ok
    end
  end

  describe "define_cvl_alerts/0" do
    test "defines only CVL-related alerts" do
      :ok = Alerts.define_cvl_alerts()

      # CVL alerts should be defined
      config = Alerts.get_config(:cvl_low_recall)
      assert config != nil
      assert config.metric == :medlum_cvl_hallucination_recall
    end

    test "returns :ok" do
      result = Alerts.define_cvl_alerts()
      assert result == :ok
    end
  end

  describe "define_eval_alerts/0" do
    test "defines only evaluation-related alerts" do
      :ok = Alerts.define_eval_alerts()

      # Eval alerts should be defined
      config = Alerts.get_config(:low_accuracy)
      assert config != nil
      assert config.metric == :medlum_eval_accuracy
    end

    test "returns :ok" do
      result = Alerts.define_eval_alerts()
      assert result == :ok
    end
  end

  describe "define_alert/2" do
    test "defines a custom alert rule" do
      :ok =
        Alerts.define_alert(:custom_alert,
          metric: :my_metric,
          condition: :greater_than,
          threshold: 100,
          severity: :critical,
          message: "Custom alert triggered"
        )

      # Should not raise
      assert true
    end

    test "uses default severity when not provided" do
      :ok =
        Alerts.define_alert(:default_severity_alert,
          metric: :my_metric,
          condition: :less_than,
          threshold: 50
        )

      # Should not raise
      assert true
    end

    test "raises when required options are missing" do
      assert_raise KeyError, fn ->
        Alerts.define_alert(:incomplete_alert,
          metric: :my_metric,
          condition: :less_than
          # missing threshold
        )
      end
    end
  end

  describe "remove_all/0" do
    test "removes all standard alert rules" do
      Alerts.define_standard_alerts()
      :ok = Alerts.remove_all()

      # Should not raise
      assert true
    end

    test "returns :ok" do
      result = Alerts.remove_all()
      assert result == :ok
    end
  end

  describe "remove/1" do
    test "removes a specific alert rule" do
      Alerts.define_standard_alerts()
      :ok = Alerts.remove(:low_accuracy)

      # Should not raise
      assert true
    end

    test "returns :ok" do
      Alerts.define_standard_alerts()
      result = Alerts.remove(:high_latency)
      assert result == :ok
    end
  end

  describe "alert_names/0" do
    test "returns list of all standard alert names" do
      names = Alerts.alert_names()

      assert is_list(names)
      assert length(names) == 6

      assert :low_accuracy in names
      assert :cvl_critical_failure in names
      assert :cvl_low_recall in names
      assert :high_latency in names
      assert :high_error_rate in names
      assert :low_consensus in names
    end
  end

  describe "get_config/1" do
    test "returns configuration for known alert" do
      config = Alerts.get_config(:low_accuracy)

      assert config.metric == :medlum_eval_accuracy
      assert config.condition == :less_than
      assert config.threshold == 0.50
      assert config.severity == :critical
      assert is_binary(config.message)
    end

    test "returns nil for unknown alert" do
      config = Alerts.get_config(:nonexistent_alert)
      assert config == nil
    end

    test "high_latency config has correct values" do
      config = Alerts.get_config(:high_latency)

      assert config.metric == :medlum_eval_inference_latency_ms
      assert config.condition == :greater_than
      assert config.threshold == 10_000
      assert config.severity == :warning
    end

    test "cvl_low_recall config has correct values" do
      config = Alerts.get_config(:cvl_low_recall)

      assert config.metric == :medlum_cvl_hallucination_recall
      assert config.condition == :less_than
      assert config.threshold == 0.80
      assert config.severity == :warning
    end
  end
end
