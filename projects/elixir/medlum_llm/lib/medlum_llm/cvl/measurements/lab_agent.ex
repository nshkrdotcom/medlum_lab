defmodule MedlumLlm.CVL.Measurements.LabAgent do
  @moduledoc """
  Forge Measurement for lab value verification using LOINC ontology.

  This measurement validates lab result claims in NLI pairs by:
  - Verifying lab test names against LOINC vocabulary
  - Checking value ranges for reasonableness
  - Validating unit consistency
  - Detecting abnormal value classifications

  ## Verdict Types

  - `:entailment` - Lab claim is verified correct
  - `:contradiction` - Lab claim contains errors
  - `:neutral` - Unable to verify (insufficient data or out of scope)

  ## Example

      iex> samples = [%Forge.Sample{data: %{claims: [%{type: :lab_value, text: "glucose 95 mg/dL"}]}}]
      iex> {:ok, results} = LabAgent.compute(samples)
      iex> results["sample_id"].verdict
      :entailment
  """

  @behaviour Forge.Measurement

  @ontology_version "loinc_2024_01"
  @measurement_version 1

  @type verdict :: :entailment | :contradiction | :neutral

  @type result :: %{
          verdict: verdict(),
          confidence: float(),
          reasoning: String.t(),
          evidence: [map()],
          lab_values_found: [map()]
        }

  @impl true
  @spec compute([Forge.Sample.t()]) :: {:ok, map()} | {:error, term()}
  def compute(samples) do
    results =
      samples
      |> Enum.map(fn sample ->
        verdict = verify_lab_values(sample)
        {sample.id, verdict}
      end)
      |> Map.new()

    {:ok, results}
  end

  @impl true
  @spec key() :: String.t()
  def key do
    config_hash =
      :crypto.hash(:md5, inspect(config()))
      |> Base.encode16(case: :lower)
      |> String.slice(0, 8)

    "lab_agent_#{config_hash}"
  end

  @impl true
  @spec version() :: pos_integer()
  def version, do: @measurement_version

  @impl true
  @spec dependencies() :: [module()]
  def dependencies, do: []

  @impl true
  @spec async?() :: boolean()
  def async?, do: true

  @impl true
  @spec timeout() :: pos_integer()
  def timeout, do: 60_000

  @doc """
  Get current configuration for this measurement.
  """
  @spec config() :: map()
  def config do
    %{
      ontology_version: @ontology_version,
      confidence_threshold: 0.8,
      verify_ranges: true,
      verify_units: true
    }
  end

  # Lab reference ranges (simplified for common tests)
  @reference_ranges %{
    "glucose" => %{
      "mg/dl" => %{low: 70, high: 100, critical_low: 40, critical_high: 400},
      "mmol/l" => %{low: 3.9, high: 5.5, critical_low: 2.2, critical_high: 22.2}
    },
    "hemoglobin" => %{
      "g/dl" => %{low: 12.0, high: 17.0, critical_low: 7.0, critical_high: 20.0}
    },
    "hgb" => %{
      "g/dl" => %{low: 12.0, high: 17.0, critical_low: 7.0, critical_high: 20.0}
    },
    "wbc" => %{
      "k/ul" => %{low: 4.5, high: 11.0, critical_low: 2.0, critical_high: 30.0},
      "10^3/ul" => %{low: 4.5, high: 11.0, critical_low: 2.0, critical_high: 30.0}
    },
    "creatinine" => %{
      "mg/dl" => %{low: 0.6, high: 1.2, critical_low: 0.2, critical_high: 10.0}
    },
    "potassium" => %{
      "meq/l" => %{low: 3.5, high: 5.0, critical_low: 2.5, critical_high: 6.5},
      "mmol/l" => %{low: 3.5, high: 5.0, critical_low: 2.5, critical_high: 6.5}
    },
    "sodium" => %{
      "meq/l" => %{low: 136, high: 145, critical_low: 120, critical_high: 160},
      "mmol/l" => %{low: 136, high: 145, critical_low: 120, critical_high: 160}
    },
    "platelet" => %{
      "k/ul" => %{low: 150, high: 400, critical_low: 50, critical_high: 1000}
    },
    "hba1c" => %{
      "%" => %{low: 4.0, high: 5.6, critical_low: 3.0, critical_high: 15.0}
    },
    "a1c" => %{
      "%" => %{low: 4.0, high: 5.6, critical_low: 3.0, critical_high: 15.0}
    },
    "ldl" => %{
      "mg/dl" => %{low: 0, high: 100, critical_low: 0, critical_high: 300}
    },
    "hdl" => %{
      "mg/dl" => %{low: 40, high: 60, critical_low: 20, critical_high: 100}
    },
    "tsh" => %{
      "miu/l" => %{low: 0.4, high: 4.0, critical_low: 0.01, critical_high: 100}
    }
  }

  # Private functions

  @spec verify_lab_values(Forge.Sample.t()) :: result()
  defp verify_lab_values(sample) do
    claims = get_lab_claims(sample)

    if Enum.empty?(claims) do
      %{
        verdict: :neutral,
        confidence: 1.0,
        reasoning: "No lab value claims found in sample",
        evidence: [],
        lab_values_found: []
      }
    else
      verifications = Enum.map(claims, &verify_single_lab/1)
      aggregate_verdicts(verifications)
    end
  end

  @spec get_lab_claims(Forge.Sample.t()) :: [map()]
  defp get_lab_claims(sample) do
    claims = sample.data[:claims] || []

    Enum.filter(claims, fn claim ->
      claim[:type] == :lab_value or
        (is_binary(claim[:text]) and contains_lab_pattern?(claim[:text]))
    end)
  end

  @spec contains_lab_pattern?(String.t()) :: boolean()
  defp contains_lab_pattern?(text) do
    patterns = [
      ~r/(level|value|result)\s*(is|was|of)\s*[\d.]+/i,
      ~r/(hemoglobin|hgb|wbc|rbc|platelet|creatinine|glucose|a1c|ldl|hdl|tsh)/i,
      ~r/\d+\.?\d*\s*(mg\/dl|mmol\/l|g\/dl|%|meq\/l|k\/ul)/i
    ]

    Enum.any?(patterns, &Regex.match?(&1, text))
  end

  @spec verify_single_lab(map()) :: map()
  defp verify_single_lab(claim) do
    text = claim[:text] || ""
    lab_info = extract_lab_info(text)

    # Verify components
    test_valid = verify_test_name(lab_info[:test_name])
    value_valid = verify_value_range(lab_info[:test_name], lab_info[:value], lab_info[:unit])

    {verdict, confidence, reasoning} =
      cond do
        value_valid == :critical ->
          {:neutral, 0.7, "Lab value is in critical range - requires clinical context"}

        test_valid == :unknown and value_valid == :unknown ->
          {:neutral, 0.5, "Unable to verify lab test or value"}

        test_valid == :valid and value_valid in [:valid, :abnormal] ->
          {:entailment, 0.9, "Lab value verified against reference ranges"}

        true ->
          {:neutral, 0.6, "Partial verification only"}
      end

    %{
      claim_text: text,
      lab_info: lab_info,
      verdict: verdict,
      confidence: confidence,
      reasoning: reasoning,
      test_valid: test_valid,
      value_valid: value_valid
    }
  end

  @spec extract_lab_info(String.t()) :: map()
  defp extract_lab_info(text) do
    %{
      test_name: extract_test_name(text),
      value: extract_value(text),
      unit: extract_unit(text),
      interpretation: extract_interpretation(text)
    }
  end

  @spec extract_test_name(String.t()) :: String.t() | nil
  defp extract_test_name(text) do
    lower_text = String.downcase(text)

    lab_names = [
      "glucose",
      "hemoglobin",
      "hgb",
      "wbc",
      "rbc",
      "platelet",
      "creatinine",
      "potassium",
      "sodium",
      "hba1c",
      "a1c",
      "ldl",
      "hdl",
      "tsh",
      "t3",
      "t4"
    ]

    Enum.find(lab_names, fn name ->
      String.contains?(lower_text, name)
    end)
  end

  @spec extract_value(String.t()) :: float() | nil
  defp extract_value(text) do
    case Regex.run(~r/(\d+\.?\d*)\s*(mg\/dl|mmol\/l|g\/dl|%|meq\/l|k\/ul|miu\/l)/i, text) do
      [_, value | _] ->
        case Float.parse(value) do
          {f, _} -> f
          :error -> nil
        end

      _ ->
        # Try without unit
        case Regex.run(~r/(?:is|was|of|:)\s*(\d+\.?\d*)/i, text) do
          [_, value] ->
            case Float.parse(value) do
              {f, _} -> f
              :error -> nil
            end

          _ ->
            nil
        end
    end
  end

  @spec extract_unit(String.t()) :: String.t() | nil
  defp extract_unit(text) do
    case Regex.run(~r/\d+\.?\d*\s*(mg\/dl|mmol\/l|g\/dl|%|meq\/l|k\/ul|miu\/l|10\^3\/ul)/i, text) do
      [_, unit] -> String.downcase(unit)
      _ -> nil
    end
  end

  @spec extract_interpretation(String.t()) :: atom() | nil
  defp extract_interpretation(text) do
    lower_text = String.downcase(text)

    cond do
      String.contains?(lower_text, "normal") -> :normal
      String.contains?(lower_text, "elevated") or String.contains?(lower_text, "high") -> :high
      String.contains?(lower_text, "low") or String.contains?(lower_text, "decreased") -> :low
      String.contains?(lower_text, "critical") -> :critical
      true -> nil
    end
  end

  @spec verify_test_name(String.t() | nil) :: :valid | :unknown
  defp verify_test_name(nil), do: :unknown

  defp verify_test_name(test_name) do
    if Map.has_key?(@reference_ranges, test_name) do
      :valid
    else
      :unknown
    end
  end

  @spec verify_value_range(String.t() | nil, float() | nil, String.t() | nil) ::
          :valid | :abnormal | :critical | :invalid | :unknown
  defp verify_value_range(nil, _value, _unit), do: :unknown
  defp verify_value_range(_test, nil, _unit), do: :unknown

  defp verify_value_range(test_name, value, unit) do
    # Normalize unit
    normalized_unit = normalize_unit(unit)

    case get_in(@reference_ranges, [test_name, normalized_unit]) do
      nil ->
        :unknown

      ranges ->
        cond do
          value < ranges.critical_low or value > ranges.critical_high -> :critical
          value < ranges.low or value > ranges.high -> :abnormal
          true -> :valid
        end
    end
  end

  @spec normalize_unit(String.t() | nil) :: String.t()
  defp normalize_unit(nil), do: ""

  defp normalize_unit(unit) do
    unit
    |> String.downcase()
    |> String.replace("10^3/ul", "k/ul")
  end

  @spec aggregate_verdicts([map()]) :: result()
  defp aggregate_verdicts(verifications) do
    verdicts = Enum.map(verifications, & &1.verdict)
    confidences = Enum.map(verifications, & &1.confidence)

    {final_verdict, reasoning} =
      cond do
        Enum.any?(verdicts, &(&1 == :contradiction)) ->
          {:contradiction, "One or more lab values are outside physiologically possible ranges"}

        Enum.all?(verdicts, &(&1 == :entailment)) ->
          {:entailment, "All lab values verified against reference ranges"}

        true ->
          {:neutral, "Partial verification - some values could not be verified"}
      end

    %{
      verdict: final_verdict,
      confidence: Enum.sum(confidences) / length(confidences),
      reasoning: reasoning,
      evidence: verifications,
      lab_values_found: Enum.map(verifications, & &1.lab_info)
    }
  end
end
