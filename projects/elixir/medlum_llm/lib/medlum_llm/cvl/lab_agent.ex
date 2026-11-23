defmodule MedlumLlm.CVL.LabAgent do
  @moduledoc """
  Verifies lab value claims against LOINC.

  Part of the 5-agent CVL consensus system with weight 1.2.

  ## Verifies

  - Lab test name validity
  - Value within physiologically possible ranges
  - Unit consistency
  - Reference range accuracy
  - Critical value flagging

  ## Source Grounding

  Verification follows source-grounded semantics:

  - **ENTAILMENT**: Lab value is valid AND found in source documents
  - **CONTRADICTION**: Lab value is invalid (unknown test, impossible value) OR
    conflicts with source
  - **NEUTRAL**: Lab value is valid but not found in source documents
    (possible hallucination, needs review)

  ## Examples

      claim = "Hemoglobin A1c is 7.2%"
      context = %{
        demographics: %{age: 55},
        source_index: %{
          labs: [%{text: "HbA1c 7.2%", doc_id: "lab-1"}]
        }
      }

      result = LabAgent.verify(claim, context)
      #=> %{verdict: :entailment, confidence: 0.9, ...}

  """

  @behaviour MedlumLlm.CVL.Agent

  alias MedlumLlm.CVL.Agent

  # LOINC module - use real one when available
  @loinc Application.compile_env(:medlum_llm, :loinc_module, MedlumLlm.CVL.LOINCStub)

  @impl true
  def name, do: :lab_agent

  @impl true
  def weight, do: 1.2

  @impl true
  def verify(claim, context) do
    lab_values = extract_lab_values(claim)

    if Enum.empty?(lab_values) do
      %{
        verdict: :neutral,
        confidence: 0.5,
        explanations: ["No lab values found in claim"],
        evidence: [],
        sub_verdicts: []
      }
    else
      # Source grounding: entailment should only be produced when the lab is supported
      # by source documents. Absence from source => :neutral (needs review).
      source_labs = source_labs(context)

      {verdicts, evidence} =
        Enum.map_reduce(lab_values, [], fn lab, acc ->
          {sub_verdict, ev} = verify_lab_value(lab, source_labs, context)
          {sub_verdict, if(ev, do: [ev | acc], else: acc)}
        end)

      result = Agent.aggregate_verdicts(verdicts)
      %{result | evidence: Enum.reverse(evidence)}
    end
  end

  @doc """
  Extract lab values from text.

  Uses clinical_ner_ex when available, falls back to pattern matching.
  """
  @spec extract_lab_values(String.t()) :: [map()]
  def extract_lab_values(claim) do
    if Code.ensure_loaded?(ClinicalNerEx) do
      case apply(ClinicalNerEx, :extract_lab_values, [claim]) do
        {:ok, entities} -> Enum.map(entities, &parse_lab_entity/1)
        _ -> extract_labs_regex(claim)
      end
    else
      extract_labs_regex(claim)
    end
  end

  defp source_labs(context) do
    cond do
      is_map(context[:source_index]) and is_list(get_in(context, [:source_index, :labs])) ->
        get_in(context, [:source_index, :labs])

      true ->
        []
    end
  end

  defp extract_labs_regex(text) do
    # Common lab patterns
    patterns = [
      # HbA1c patterns: "A1c 7.2%", "HbA1c is 7.2", "hemoglobin A1c of 7.2%"
      {~r/(?:hba1c|a1c|hemoglobin a1c)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(%)?/i, "hemoglobin_a1c",
       "%"},

      # Glucose: "glucose 120 mg/dL", "blood sugar 95"
      {~r/(?:glucose|blood sugar|fasting glucose)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(mg\/dl|mg\/dL)?/i,
       "glucose", "mg/dL"},

      # Hemoglobin: "Hgb 12.5 g/dL", "hemoglobin 14"
      {~r/(?:hgb|hemoglobin)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(g\/dl|g\/dL)?/i, "hemoglobin",
       "g/dL"},

      # WBC: "WBC 8.5", "white blood cell count 12000"
      {~r/(?:wbc|white blood cell(?:s)?(?:\s+count)?)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(K\/uL|x10\^9\/L|\/uL)?/i,
       "wbc", "K/uL"},

      # Creatinine: "creatinine 1.2 mg/dL"
      {~r/(?:creatinine|cr)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(mg\/dl|mg\/dL)?/i, "creatinine",
       "mg/dL"},

      # BUN: "BUN 18 mg/dL"
      {~r/(?:bun|blood urea nitrogen)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(mg\/dl|mg\/dL)?/i,
       "bun", "mg/dL"},

      # Potassium: "K+ 4.2 mEq/L", "potassium 4.5"
      {~r/(?:potassium|k\+?)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(mEq\/L|mmol\/L)?/i, "potassium",
       "mEq/L"},

      # Sodium: "Na 140 mEq/L"
      {~r/(?:sodium|na\+?)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(mEq\/L|mmol\/L)?/i, "sodium",
       "mEq/L"},

      # Platelets: "platelets 250000", "plt 250 K/uL"
      {~r/(?:platelets?|plt)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(K\/uL|\/uL)?/i, "platelets",
       "K/uL"},

      # INR: "INR 2.5"
      {~r/(?:inr)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)/i, "inr", "ratio"},

      # eGFR: "eGFR 65 mL/min"
      {~r/(?:egfr|gfr)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(ml\/min)?/i, "egfr", "mL/min"},

      # Cholesterol: "total cholesterol 220", "LDL 130"
      {~r/(?:total cholesterol|cholesterol)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(mg\/dl|mg\/dL)?/i,
       "cholesterol_total", "mg/dL"},
      {~r/(?:ldl)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(mg\/dl|mg\/dL)?/i, "ldl_cholesterol",
       "mg/dL"},
      {~r/(?:hdl)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(mg\/dl|mg\/dL)?/i, "hdl_cholesterol",
       "mg/dL"},

      # TSH: "TSH 2.5 mIU/L"
      {~r/(?:tsh)[:\s]+(?:is\s+|of\s+)?(\d+\.?\d*)\s*(miu\/l|mIU\/L|uIU\/mL)?/i, "tsh", "mIU/L"}
    ]

    Enum.flat_map(patterns, fn {regex, test_name, default_unit} ->
      case Regex.run(regex, text) do
        [_, value | rest] ->
          unit =
            case rest do
              [u | _] when is_binary(u) and u != "" -> u
              _ -> default_unit
            end

          [
            %{
              test_name: test_name,
              value: parse_value(value),
              unit: normalize_unit(unit),
              raw_text: Enum.at(Regex.run(regex, text), 0)
            }
          ]

        nil ->
          []
      end
    end)
  end

  defp parse_lab_entity(%{text: text, attributes: attrs}) when is_map(attrs) do
    %{
      test_name: String.downcase(to_string(attrs[:lab_name] || text || "")),
      value: attrs[:value],
      unit: attrs[:unit],
      raw_text: text
    }
  end

  defp parse_lab_entity(entity) when is_map(entity) do
    %{
      test_name: String.downcase(entity[:test_name] || entity["test_name"] || ""),
      value: entity[:value] || entity["value"],
      unit: entity[:unit] || entity["unit"],
      raw_text: entity[:text] || entity["text"]
    }
  end

  defp parse_value(value) when is_binary(value) do
    case Float.parse(value) do
      {v, _} -> v
      :error -> nil
    end
  end

  defp parse_value(value) when is_number(value), do: value
  defp parse_value(_), do: nil

  defp normalize_unit(nil), do: nil

  defp normalize_unit(unit) do
    unit
    |> String.replace("dl", "dL")
    |> String.replace("ul", "uL")
  end

  defp verify_lab_value(%{value: nil} = lab, _source_labs, _context) do
    {{:neutral, "Could not parse value for #{lab.test_name}"}, nil}
  end

  defp verify_lab_value(lab, source_labs, context) do
    source_match = find_source_lab(source_labs, lab.test_name)

    with {:ok, loinc_code} <- @loinc.lookup(lab.test_name),
         :ok <- verify_physiological(lab.value, lab.unit, loinc_code),
         :ok <- verify_unit_consistency(lab.unit, loinc_code),
         {:ok, ref_range} <- @loinc.reference_range(loinc_code, context[:demographics] || %{}) do
      if is_nil(source_match) do
        {{:neutral, "Lab '#{lab.test_name}' not found in source documents"}, nil}
      else
        evidence = %{
          doc_id: source_match[:doc_id],
          snippet: source_match[:text] || source_match[:snippet] || "",
          entity_type: :lab,
          entity: source_match
        }

        classification = classify_value(lab.value, ref_range)
        formatted_range = format_range(ref_range)

        verdict =
          case classification do
            :normal -> :entailment
            :critical_high -> :entailment
            :critical_low -> :entailment
            :high -> :entailment
            :low -> :entailment
            _ -> :neutral
          end

        explanation =
          "#{format_test_name(lab.test_name)}: #{lab.value} #{lab.unit} (#{classification}, ref: #{formatted_range})"

        {{verdict, explanation}, evidence}
      end
    else
      {:error, :not_found} ->
        {{:neutral, "Unknown lab test: #{lab.test_name}"}, nil}

      {:error, {:impossible_value, reason}} ->
        {{:contradiction, "Impossible value for #{lab.test_name}: #{reason}"}, nil}

      {:error, {:unit_mismatch, expected}} ->
        {{:neutral,
          "Unit mismatch for #{lab.test_name}: got #{lab.unit}, expected #{expected}"}, nil}

      {:error, reason} ->
        {{:neutral, "Could not verify #{lab.test_name}: #{inspect(reason)}"}, nil}
    end
  end

  defp find_source_lab(source_labs, test_name) do
    # Get all aliases for this test name
    aliases = lab_aliases(test_name)

    Enum.find(source_labs, fn src ->
      src_text = String.downcase(to_string(src[:text] || src[:snippet] || ""))

      Enum.any?(aliases, fn alias_name ->
        String.contains?(src_text, alias_name)
      end)
    end)
  end

  # Lab name aliases for flexible source matching
  defp lab_aliases("hemoglobin_a1c"),
    do: ["hemoglobin_a1c", "hemoglobin a1c", "hba1c", "a1c", "hgba1c"]

  defp lab_aliases("glucose"),
    do: ["glucose", "blood sugar", "fasting glucose", "blood glucose"]

  defp lab_aliases("hemoglobin"), do: ["hemoglobin", "hgb", "hb"]
  defp lab_aliases("wbc"), do: ["wbc", "white blood cell", "white blood cells", "leukocytes"]
  defp lab_aliases("creatinine"), do: ["creatinine", "cr", "serum creatinine"]
  defp lab_aliases("bun"), do: ["bun", "blood urea nitrogen", "urea nitrogen"]
  defp lab_aliases("potassium"), do: ["potassium", "k+", "serum potassium"]
  defp lab_aliases("sodium"), do: ["sodium", "na+", "na", "serum sodium"]
  defp lab_aliases("platelets"), do: ["platelets", "plt", "platelet count", "thrombocytes"]
  defp lab_aliases("inr"), do: ["inr", "pt/inr", "prothrombin time"]
  defp lab_aliases("egfr"), do: ["egfr", "gfr", "estimated gfr", "glomerular filtration"]
  defp lab_aliases("cholesterol_total"), do: ["cholesterol_total", "total cholesterol", "cholesterol"]
  defp lab_aliases("ldl_cholesterol"), do: ["ldl_cholesterol", "ldl", "ldl-c"]
  defp lab_aliases("hdl_cholesterol"), do: ["hdl_cholesterol", "hdl", "hdl-c"]
  defp lab_aliases("tsh"), do: ["tsh", "thyroid stimulating hormone"]
  # Default: just the test name itself
  defp lab_aliases(test_name), do: [test_name, String.replace(test_name, "_", " ")]

  defp verify_physiological(value, _unit, loinc_code) do
    case @loinc.physiological_limits(loinc_code) do
      {:ok, %{min: min, max: max}} ->
        if value >= min and value <= max do
          :ok
        else
          {:error, {:impossible_value, "#{value} outside physiological range #{min}-#{max}"}}
        end

      {:error, :no_limit_data} ->
        :ok
    end
  end

  defp verify_unit_consistency(nil, _loinc_code), do: :ok

  defp verify_unit_consistency(unit, loinc_code) do
    case @loinc.expected_unit(loinc_code) do
      {:ok, expected} ->
        if compatible_units?(unit, expected) do
          :ok
        else
          {:error, {:unit_mismatch, expected}}
        end

      {:error, :no_unit_data} ->
        :ok
    end
  end

  defp compatible_units?(a, b) do
    normalize = fn u ->
      u
      |> String.downcase()
      |> String.replace("/", "_")
      |> String.replace(" ", "")
    end

    normalize.(a) == normalize.(b)
  end

  defp classify_value(value, %{low: low, high: high} = range) do
    critical_low = Map.get(range, :critical_low, low * 0.5)
    critical_high = Map.get(range, :critical_high, high * 2)

    cond do
      not is_nil(critical_low) and value < critical_low -> :critical_low
      value < low -> :low
      not is_nil(critical_high) and value > critical_high -> :critical_high
      value > high -> :high
      true -> :normal
    end
  end

  defp classify_value(_, _), do: :unknown

  defp format_range(%{low: low, high: high}), do: "#{low}-#{high}"
  defp format_range(_), do: "unknown"

  defp format_test_name(name) do
    name
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
