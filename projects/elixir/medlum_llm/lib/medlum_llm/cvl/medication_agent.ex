defmodule MedlumLlm.CVL.MedicationAgent do
  @moduledoc """
  Verifies medication claims against RxNorm.

  Part of the 5-agent CVL consensus system. Has the highest weight (1.5)
  because medication errors are the most safety-critical.

  ## Verifies

  - Drug name existence and spelling
  - Dosage validity (within therapeutic ranges)
  - Frequency plausibility
  - Drug-drug interaction flags
  - Contraindication warnings

  ## Source Grounding

  Verification follows source-grounded semantics:

  - **ENTAILMENT**: Medication is valid AND found in source documents
  - **CONTRADICTION**: Medication is invalid (unknown drug, unsafe dose) OR
    conflicts with source
  - **NEUTRAL**: Medication is valid but not found in source documents
    (possible hallucination, needs review)

  ## Examples

      claim = "Patient started on Metformin 500mg twice daily"
      context = %{
        conditions: [:diabetes],
        current_medications: [],
        source_index: %{
          medications: [%{text: "metformin 500 mg BID", doc_id: "note-1"}]
        }
      }

      result = MedicationAgent.verify(claim, context)
      #=> %{verdict: :entailment, confidence: 0.95, ...}

  """

  @behaviour MedlumLlm.CVL.Agent

  alias MedlumLlm.CVL.Agent

  # RxNorm module - use real one when available
  @rxnorm Application.compile_env(:medlum_llm, :rxnorm_module, MedlumLlm.CVL.RxNormStub)

  @impl true
  def name, do: :medication_agent

  @impl true
  def weight, do: 1.5

  @impl true
  def verify(claim, context) do
    medications = extract_medications(claim)

    if Enum.empty?(medications) do
      %{
        verdict: :neutral,
        confidence: 0.5,
        explanations: ["No medication mentions found in claim"],
        evidence: [],
        sub_verdicts: []
      }
    else
      # Source grounding: entailment/contradiction should be backed by source evidence when possible.
      # If a medication is plausible but absent from source documents, return :neutral (needs review).
      source_meds = source_medications(context)

      {verdicts, evidence} =
        Enum.map_reduce(medications, [], fn med, acc ->
          {sub_verdict, ev} = verify_medication(med, source_meds, context)
          {sub_verdict, if(ev, do: [ev | acc], else: acc)}
        end)

      result = Agent.aggregate_verdicts(verdicts)
      %{result | evidence: Enum.reverse(evidence)}
    end
  end

  @doc """
  Extract medication mentions from text.

  Uses clinical_ner_ex when available, falls back to regex patterns.
  """
  @spec extract_medications(String.t()) :: [map()]
  def extract_medications(claim) do
    if Code.ensure_loaded?(ClinicalNerEx) do
      case apply(ClinicalNerEx, :extract_medications, [claim]) do
        {:ok, entities} -> Enum.map(entities, &parse_medication_entity/1)
        _ -> extract_medications_regex(claim)
      end
    else
      extract_medications_regex(claim)
    end
  end

  defp source_medications(context) do
    cond do
      is_map(context[:source_index]) and is_list(get_in(context, [:source_index, :medications])) ->
        get_in(context, [:source_index, :medications])

      true ->
        []
    end
  end

  defp extract_medications_regex(text) do
    # Pattern: drug name optionally followed by dose and frequency
    # Examples: "metformin", "metformin 500mg", "metformin 500mg twice daily"
    pattern =
      ~r/\b([A-Za-z]+(?:in|ol|ide|ine|ate|one|mab|nib|pril|sartan|statin|oxacin|cillin|mycin))\s*(?:(\d+(?:\.\d+)?)\s*(mg|g|mcg|units?|ml|IU))?\s*((?:once|twice|three times|four times|qd|bid|tid|qid|daily|weekly|monthly)?)?/i

    Regex.scan(pattern, text)
    |> Enum.map(fn match ->
      [_, name | rest] = match
      dose = Enum.at(rest, 0)
      unit = Enum.at(rest, 1)
      frequency = Enum.at(rest, 2)

      %{
        name: String.downcase(name),
        dose: parse_dose(dose),
        unit: unit,
        frequency: normalize_frequency(frequency),
        raw_text: Enum.at(match, 0)
      }
    end)
    |> Enum.uniq_by(& &1.name)
  end

  defp parse_medication_entity(%{text: text, attributes: attrs}) when is_map(attrs) do
    %{
      name: String.downcase(to_string(attrs[:drug_name] || text || "")),
      dose: attrs[:dose],
      unit: attrs[:dose_unit] || attrs[:unit],
      frequency: attrs[:frequency],
      raw_text: text
    }
  end

  defp parse_medication_entity(entity) when is_map(entity) do
    %{
      name: String.downcase(entity[:text] || entity["text"] || ""),
      dose: entity[:dose] || entity["dose"],
      unit: entity[:unit] || entity["unit"],
      frequency: entity[:frequency] || entity["frequency"],
      raw_text: entity[:text] || entity["text"]
    }
  end

  defp parse_dose(nil), do: nil

  defp parse_dose(dose) when is_binary(dose) do
    case Float.parse(dose) do
      {value, _} -> value
      :error -> nil
    end
  end

  defp parse_dose(dose) when is_number(dose), do: dose

  defp normalize_frequency(nil), do: nil
  defp normalize_frequency(""), do: nil

  defp normalize_frequency(freq) do
    freq = String.downcase(freq)

    cond do
      freq in ["qd", "daily", "once daily", "once"] -> "daily"
      freq in ["bid", "twice daily", "twice"] -> "twice_daily"
      freq in ["tid", "three times daily", "three times"] -> "three_times_daily"
      freq in ["qid", "four times daily", "four times"] -> "four_times_daily"
      freq in ["weekly"] -> "weekly"
      freq in ["monthly"] -> "monthly"
      true -> freq
    end
  end

  defp verify_medication(med, source_meds, context) do
    source_match = find_source_medication(source_meds, med.name)

    with {:ok, rxcui} <- @rxnorm.lookup(med.name) do
      if is_nil(source_match) do
        # Medication is valid in RxNorm but not found in source documents
        # This is a potential hallucination - return neutral for review
        {{:neutral, "Medication '#{med.name}' not found in source documents"}, nil}
      else
        evidence = %{
          doc_id: source_match[:doc_id],
          snippet: source_match[:text] || source_match[:snippet] || "",
          entity_type: :medication,
          entity: source_match
        }

        with :ok <- verify_dose(med, rxcui),
             :ok <- verify_frequency(med, rxcui),
             :ok <- check_interactions(med, context[:current_medications] || []),
             :ok <- check_contraindications(med, context[:conditions] || []) do
          {{:entailment, "Medication '#{med.name}' supported by source documents"}, evidence}
        else
          {:error, {:invalid_dose, reason}} ->
            {{:contradiction, "Invalid dose for '#{med.name}': #{reason}"}, evidence}

          {:error, {:unusual_frequency, freq}} ->
            {{:neutral, "Unusual frequency for '#{med.name}': #{freq}"}, evidence}

          {:error, {:interaction, drugs}} ->
            {{:neutral, "Potential interaction: '#{med.name}' with #{inspect(drugs)}"}, evidence}

          {:error, {:contraindication, condition}} ->
            {{:contradiction, "Contraindication: '#{med.name}' with #{condition}"}, evidence}

          {:error, reason} ->
            {{:neutral, "Could not fully verify '#{med.name}': #{inspect(reason)}"}, evidence}
        end
      end
    else
      {:error, :not_found} ->
        {{:contradiction, "Unknown medication: '#{med.name}' not found in RxNorm"}, nil}

      {:error, reason} ->
        {{:neutral, "Could not validate medication '#{med.name}': #{inspect(reason)}"}, nil}
    end
  end

  defp find_source_medication(source_meds, name) do
    Enum.find(source_meds, fn src ->
      src_text = to_string(src[:text] || src[:snippet] || "")
      String.contains?(String.downcase(src_text), String.downcase(name))
    end)
  end

  defp verify_dose(%{dose: nil}, _rxcui), do: :ok

  defp verify_dose(%{dose: dose, unit: unit}, rxcui) do
    case @rxnorm.therapeutic_range(rxcui) do
      {:ok, %{min: min, max: max, unit: expected_unit}} ->
        normalized_dose = normalize_dose_unit(dose, unit, expected_unit)

        if normalized_dose >= min and normalized_dose <= max do
          :ok
        else
          {:error,
           {:invalid_dose, "#{dose}#{unit} outside therapeutic range #{min}-#{max}#{expected_unit}"}}
        end

      {:error, :no_range_data} ->
        # No range data available, allow
        :ok

      error ->
        error
    end
  end

  defp verify_frequency(%{frequency: nil}, _rxcui), do: :ok

  defp verify_frequency(%{frequency: freq}, rxcui) do
    case @rxnorm.typical_frequencies(rxcui) do
      {:ok, frequencies} ->
        if freq in frequencies do
          :ok
        else
          {:error, {:unusual_frequency, freq}}
        end

      {:error, :no_frequency_data} ->
        :ok

      error ->
        error
    end
  end

  defp check_interactions(%{name: name}, current_medications) when is_list(current_medications) do
    current_names =
      Enum.map(current_medications, fn m ->
        m[:name] || m["name"] || ""
      end)

    case @rxnorm.check_interactions(name, current_names) do
      {:ok, []} -> :ok
      {:ok, interactions} -> {:error, {:interaction, interactions}}
      {:error, :no_interaction_data} -> :ok
      error -> error
    end
  end

  defp check_interactions(_, _), do: :ok

  defp check_contraindications(%{name: name}, conditions) when is_list(conditions) do
    condition_names =
      Enum.map(conditions, fn c ->
        cond do
          is_atom(c) -> Atom.to_string(c)
          is_binary(c) -> c
          is_map(c) -> c[:name] || c["name"] || ""
          true -> ""
        end
      end)

    case @rxnorm.check_contraindications(name, condition_names) do
      {:ok, []} -> :ok
      {:ok, [contra | _]} -> {:error, {:contraindication, contra}}
      {:error, :no_contraindication_data} -> :ok
      error -> error
    end
  end

  defp check_contraindications(_, _), do: :ok

  defp normalize_dose_unit(dose, from_unit, to_unit) when from_unit == to_unit, do: dose
  defp normalize_dose_unit(dose, "g", "mg"), do: dose * 1000
  defp normalize_dose_unit(dose, "mg", "g"), do: dose / 1000
  defp normalize_dose_unit(dose, "mcg", "mg"), do: dose / 1000
  defp normalize_dose_unit(dose, "mg", "mcg"), do: dose * 1000
  defp normalize_dose_unit(dose, _, _), do: dose
end
