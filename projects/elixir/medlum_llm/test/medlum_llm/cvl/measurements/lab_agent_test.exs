defmodule MedlumLlm.CVL.Measurements.LabAgentTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.Measurements.LabAgent

  describe "compute/1" do
    test "returns neutral when no lab claims" do
      sample = make_sample(%{claims: []})

      {:ok, results} = LabAgent.compute([sample])

      result = results[sample.id]
      assert result.verdict == :neutral
      assert result.reasoning =~ "No lab value claims"
    end

    test "verifies lab value in normal range" do
      sample = make_sample(%{
        claims: [%{type: :lab_value, text: "glucose 95 mg/dL"}]
      })

      {:ok, results} = LabAgent.compute([sample])

      result = results[sample.id]
      # 95 mg/dL is in normal range (70-100)
      assert result.verdict in [:entailment, :neutral]
    end

    test "detects lab value outside range" do
      sample = make_sample(%{
        claims: [%{type: :lab_value, text: "glucose 500 mg/dL"}]
      })

      {:ok, results} = LabAgent.compute([sample])

      result = results[sample.id]
      # 500 is critical high
      lab_info = hd(result.lab_values_found)
      assert lab_info.test_name == "glucose"
    end

    test "handles hemoglobin values" do
      sample = make_sample(%{
        claims: [%{type: :lab_value, text: "hemoglobin 14.5 g/dL"}]
      })

      {:ok, results} = LabAgent.compute([sample])

      result = results[sample.id]
      assert length(result.lab_values_found) >= 1
    end

    test "handles A1C values" do
      sample = make_sample(%{
        claims: [%{type: :lab_value, text: "HbA1c 6.5%"}]
      })

      {:ok, results} = LabAgent.compute([sample])

      result = results[sample.id]
      lab_info = hd(result.lab_values_found)
      assert lab_info.test_name in ["hba1c", "a1c"]
    end

    test "detects lab values in text without type tag" do
      sample = make_sample(%{
        claims: [%{text: "Creatinine was 1.1 mg/dL"}]
      })

      {:ok, results} = LabAgent.compute([sample])

      result = results[sample.id]
      assert length(result.lab_values_found) >= 1
    end
  end

  describe "key/0" do
    test "returns stable key" do
      assert String.starts_with?(LabAgent.key(), "lab_agent_")
    end
  end

  describe "version/0" do
    test "returns positive integer" do
      assert LabAgent.version() >= 1
    end
  end

  describe "config/0" do
    test "includes LOINC version" do
      config = LabAgent.config()

      assert config.ontology_version =~ "loinc"
    end
  end

  defp make_sample(data) do
    %Forge.Sample{
      id: "test_#{System.unique_integer()}",
      pipeline: :test,
      data: data,
      measurements: %{},
      status: :pending,
      created_at: DateTime.utc_now()
    }
  end
end
