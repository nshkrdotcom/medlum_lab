defmodule MedOntology.Client.RxNavBehaviour do
  @moduledoc """
  Behaviour for RxNav API client.

  Extends the base client behaviour with RxNorm-specific operations like
  drug normalization, ingredient lookup, drug class retrieval, NDC mapping,
  and drug-drug interaction checking.

  ## Note

  This behaviour includes all callbacks needed for mocking in tests.
  The base client callbacks (get_concept, search, health_check) are included
  to allow the mock to be a complete implementation.
  """

  # Base client callbacks (included for complete mock implementation)
  @callback get_concept(rxcui :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback search(query :: String.t(), opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback health_check() :: :ok | {:error, term()}

  # RxNorm-specific callbacks
  @doc """
  Get RxCUI for a drug name (exact or approximate match).
  """
  @callback get_rxcui(drug_string :: String.t()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Get drug ingredients for an RxCUI.
  """
  @callback get_ingredients(rxcui :: String.t()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Get drug class information.
  """
  @callback get_drug_class(rxcui :: String.t(), class_type :: String.t()) ::
              {:ok, [map()]} | {:error, term()}

  @doc """
  Get NDC codes for an RxCUI.
  """
  @callback get_ndc(rxcui :: String.t()) :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Get drug-drug interactions between RxCUIs.
  """
  @callback get_interactions(rxcui1 :: String.t(), rxcui2 :: String.t()) ::
              {:ok, [map()]} | {:error, term()}
end
