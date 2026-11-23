defmodule MedlumLlm.CVL.RxNormStub do
  @moduledoc """
  Stub implementation of RxNorm lookup.

  Will be replaced by med_ontology_ex when available.
  Provides basic validation using a small in-memory dictionary.

  ## Supported Medications

  This stub supports a limited set of common medications for testing:

  - metformin - Diabetes management
  - lisinopril - ACE inhibitor for hypertension
  - aspirin - Antiplatelet/analgesic
  - atorvastatin - Statin for cholesterol
  - omeprazole - Proton pump inhibitor
  - amlodipine - Calcium channel blocker
  - warfarin - Anticoagulant
  - insulin - Diabetes management

  ## Production Use

  In production, configure `:medlum_llm` to use `MedOntologyEx.RxNorm`:

      config :medlum_llm,
        rxnorm_module: MedOntologyEx.RxNorm

  """

  # Common medications with RXCUIs and basic info
  @medications %{
    "metformin" => %{
      rxcui: "6809",
      therapeutic_range: %{min: 500, max: 2550, unit: "mg"},
      frequencies: ["daily", "twice_daily", "three_times_daily"],
      contraindications: ["renal_failure", "liver_disease"],
      interactions: []
    },
    "lisinopril" => %{
      rxcui: "29046",
      therapeutic_range: %{min: 2.5, max: 40, unit: "mg"},
      frequencies: ["daily"],
      contraindications: ["angioedema", "pregnancy"],
      interactions: ["potassium", "spironolactone"]
    },
    "aspirin" => %{
      rxcui: "1191",
      therapeutic_range: %{min: 81, max: 650, unit: "mg"},
      frequencies: ["daily", "four_times_daily"],
      contraindications: ["bleeding_disorder", "gi_ulcer"],
      interactions: ["warfarin", "ibuprofen"]
    },
    "atorvastatin" => %{
      rxcui: "83367",
      therapeutic_range: %{min: 10, max: 80, unit: "mg"},
      frequencies: ["daily"],
      contraindications: ["liver_disease", "pregnancy"],
      interactions: ["gemfibrozil", "niacin"]
    },
    "omeprazole" => %{
      rxcui: "7646",
      therapeutic_range: %{min: 20, max: 40, unit: "mg"},
      frequencies: ["daily", "twice_daily"],
      contraindications: [],
      interactions: ["clopidogrel"]
    },
    "amlodipine" => %{
      rxcui: "17767",
      therapeutic_range: %{min: 2.5, max: 10, unit: "mg"},
      frequencies: ["daily"],
      contraindications: [],
      interactions: ["simvastatin"]
    },
    "warfarin" => %{
      rxcui: "11289",
      therapeutic_range: %{min: 1, max: 10, unit: "mg"},
      frequencies: ["daily"],
      contraindications: ["bleeding_disorder", "pregnancy"],
      interactions: ["aspirin", "vitamin_k", "nsaids"]
    },
    "insulin" => %{
      rxcui: "5856",
      # Highly variable based on patient needs
      therapeutic_range: nil,
      frequencies: ["daily", "twice_daily", "three_times_daily", "four_times_daily"],
      contraindications: [],
      interactions: []
    }
  }

  @doc """
  Look up medication in RxNorm.

  Returns the RXCUI (RxNorm Concept Unique Identifier) for a medication name.

  ## Examples

      iex> RxNormStub.lookup("metformin")
      {:ok, "6809"}

      iex> RxNormStub.lookup("fakemedicine")
      {:error, :not_found}

  """
  @spec lookup(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def lookup(name) do
    normalized = String.downcase(name)

    case Map.fetch(@medications, normalized) do
      {:ok, info} -> {:ok, info.rxcui}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Get therapeutic dose range for medication.

  Returns the typical safe dose range for a given RXCUI.

  ## Examples

      iex> RxNormStub.therapeutic_range("6809")
      {:ok, %{min: 500, max: 2550, unit: "mg"}}

      iex> RxNormStub.therapeutic_range("5856")  # insulin
      {:error, :no_range_data}

  """
  @spec therapeutic_range(String.t()) :: {:ok, map()} | {:error, :no_range_data}
  def therapeutic_range(rxcui) do
    med = find_by_rxcui(rxcui)

    case med do
      nil -> {:error, :no_range_data}
      %{therapeutic_range: nil} -> {:error, :no_range_data}
      %{therapeutic_range: range} -> {:ok, range}
    end
  end

  @doc """
  Get typical frequencies for medication.

  Returns a list of typical dosing frequencies for a given RXCUI.

  ## Examples

      iex> RxNormStub.typical_frequencies("6809")
      {:ok, ["daily", "twice_daily", "three_times_daily"]}

  """
  @spec typical_frequencies(String.t()) :: {:ok, [String.t()]} | {:error, :no_frequency_data}
  def typical_frequencies(rxcui) do
    case find_by_rxcui(rxcui) do
      nil -> {:error, :no_frequency_data}
      %{frequencies: freqs} -> {:ok, freqs}
    end
  end

  @doc """
  Check for drug-drug interactions.

  Returns a list of interacting drugs from the provided list.

  ## Examples

      iex> RxNormStub.check_interactions("aspirin", ["warfarin", "metformin"])
      {:ok, ["warfarin"]}

      iex> RxNormStub.check_interactions("metformin", ["lisinopril"])
      {:ok, []}

  """
  @spec check_interactions(String.t(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, :no_interaction_data}
  def check_interactions(drug_name, other_drugs) do
    normalized = String.downcase(drug_name)

    case Map.fetch(@medications, normalized) do
      {:ok, %{interactions: interactions}} ->
        other_normalized = Enum.map(other_drugs, &String.downcase/1)
        found = Enum.filter(interactions, &(&1 in other_normalized))
        {:ok, found}

      :error ->
        {:error, :no_interaction_data}
    end
  end

  @doc """
  Check for contraindications.

  Returns a list of contraindicated conditions from the provided list.

  ## Examples

      iex> RxNormStub.check_contraindications("metformin", ["renal failure"])
      {:ok, ["renal_failure"]}

      iex> RxNormStub.check_contraindications("aspirin", ["diabetes"])
      {:ok, []}

  """
  @spec check_contraindications(String.t(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, :no_contraindication_data}
  def check_contraindications(drug_name, conditions) do
    normalized = String.downcase(drug_name)

    case Map.fetch(@medications, normalized) do
      {:ok, %{contraindications: contras}} ->
        condition_normalized =
          Enum.map(conditions, fn c ->
            c |> String.downcase() |> String.replace(" ", "_")
          end)

        found = Enum.filter(contras, &(&1 in condition_normalized))
        {:ok, found}

      :error ->
        {:error, :no_contraindication_data}
    end
  end

  defp find_by_rxcui(rxcui) do
    @medications
    |> Enum.find(fn {_, v} -> v.rxcui == rxcui end)
    |> case do
      nil -> nil
      {_, info} -> info
    end
  end
end
