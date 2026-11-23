defmodule MedlumLlm.CVL.Measurements.MedicationAgentTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.Measurements.MedicationAgent

  describe "compute/1" do
    test "returns neutral when no medication claims" do
      sample = make_sample(%{claims: []})

      {:ok, results} = MedicationAgent.compute([sample])

      result = results[sample.id]
      assert result.verdict == :neutral
      assert result.reasoning =~ "No medication claims"
    end

    test "verifies known medication" do
      sample = make_sample(%{
        claims: [%{type: :medication, text: "Patient takes metformin 500mg daily"}]
      })

      {:ok, results} = MedicationAgent.compute([sample])

      result = results[sample.id]
      # Metformin is in the known drugs list
      assert result.verdict in [:entailment, :neutral]
    end

    test "detects medication in text even without type tag" do
      sample = make_sample(%{
        claims: [%{text: "Started lisinopril 10mg oral daily"}]
      })

      {:ok, results} = MedicationAgent.compute([sample])

      result = results[sample.id]
      assert length(result.medications_found) >= 1
    end

    test "handles multiple medications" do
      sample = make_sample(%{
        claims: [
          %{type: :medication, text: "Takes metformin 500mg twice daily"},
          %{type: :medication, text: "Takes lisinopril 10mg daily"}
        ]
      })

      {:ok, results} = MedicationAgent.compute([sample])

      result = results[sample.id]
      assert length(result.evidence) == 2
    end

    test "processes multiple samples" do
      samples = [
        make_sample(%{claims: [%{type: :medication, text: "metformin 500mg"}]}),
        make_sample(%{claims: [%{type: :medication, text: "lisinopril 10mg"}]})
      ]

      {:ok, results} = MedicationAgent.compute(samples)

      assert map_size(results) == 2
    end
  end

  describe "key/0" do
    test "returns stable key for same config" do
      key1 = MedicationAgent.key()
      key2 = MedicationAgent.key()

      assert key1 == key2
      assert String.starts_with?(key1, "medication_agent_")
    end
  end

  describe "version/0" do
    test "returns positive integer" do
      assert MedicationAgent.version() >= 1
    end
  end

  describe "dependencies/0" do
    test "returns empty list" do
      assert MedicationAgent.dependencies() == []
    end
  end

  describe "config/0" do
    test "includes ontology version" do
      config = MedicationAgent.config()

      assert config.ontology_version =~ "rxnorm"
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
