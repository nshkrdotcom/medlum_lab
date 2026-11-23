defmodule MedlumLlm.CVL.Stages.PIIRedaction do
  @moduledoc """
  Forge Stage for HIPAA-compliant PII redaction.

  This stage uses `MedlumLlm.Guardrails.Redactor` to remove Protected Health
  Information (PHI) from samples before export. Redaction is applied to all
  text fields while preserving medical terminology.

  ## Redaction Modes

  - `:automatic` - Standard mode using Tier 1 + Tier 2 patterns
  - `:aggressive` - Uses all patterns including Tier 3 (names, facilities)
  - `:hipaa_safe_harbor` - Strict mode covering all 18 HIPAA identifiers

  ## Configuration Options

  - `:mode` - Redaction mode (default: `:automatic`)
  - `:replacement_style` - How to replace PHI (`:placeholder`, `:hash`, `:mask`)
  - `:seed` - Seed for deterministic pseudonymization
  - `:audit` - Whether to generate audit manifest (default: `true`)

  ## Example

      iex> sample = %Forge.Sample{data: %{
      ...>   source_document: "Patient John Smith, MRN: 12345678"
      ...> }}
      iex> {:ok, redacted} = PIIRedaction.process(sample)
      iex> redacted.data.source_document
      "Patient [PROVIDER_REDACTED], [MRN_REDACTED]"
  """

  @behaviour Forge.Stage

  alias MedlumLlm.Guardrails.Redactor

  @text_fields [
    :source_document,
    :generated_summary,
    :question,
    :gold_answer,
    :predicted_answer,
    :premise,
    :hypothesis
  ]

  @impl true
  @spec process(Forge.Sample.t()) :: {:ok, Forge.Sample.t()} | {:skip, term()} | {:error, term()}
  def process(sample) do
    process(sample, [])
  end

  @spec process(Forge.Sample.t(), keyword()) ::
          {:ok, Forge.Sample.t()} | {:skip, term()} | {:error, term()}
  def process(sample, opts) do
    mode = Keyword.get(opts, :mode, :aggressive)
    audit = Keyword.get(opts, :audit, true)

    redactor_opts =
      opts
      |> Keyword.take([:seed, :replacement_style, :date_shift_days])
      |> Keyword.put(:mode, mode)

    # Redact all text fields
    {redacted_data, manifests} = redact_all_fields(sample.data, redactor_opts, audit)

    # Also redact text in NLI pairs if present
    redacted_data = redact_nli_pairs(redacted_data, redactor_opts)

    # Also redact text in claims if present
    redacted_data = redact_claims(redacted_data, redactor_opts)

    # Add redaction metadata
    updated_data =
      if audit do
        Map.put(redacted_data, :redaction_manifests, manifests)
      else
        redacted_data
      end

    {:ok, %{sample | data: updated_data}}
  rescue
    e ->
      {:error, %{reason: :redaction_failed, exception: Exception.message(e)}}
  end

  @impl true
  @spec async?() :: boolean()
  def async?, do: false

  @impl true
  @spec concurrency() :: pos_integer()
  def concurrency, do: 1

  @impl true
  @spec timeout() :: pos_integer()
  def timeout, do: 30_000

  # Private functions

  @spec redact_all_fields(map(), keyword(), boolean()) :: {map(), map()}
  defp redact_all_fields(data, opts, audit) do
    Enum.reduce(@text_fields, {data, %{}}, fn field, {acc_data, acc_manifests} ->
      case Map.get(acc_data, field) do
        nil ->
          {acc_data, acc_manifests}

        text when is_binary(text) and text != "" ->
          {redacted, manifest} = redact_text(text, opts, audit)

          new_data = Map.put(acc_data, field, redacted)

          new_manifests =
            if audit and manifest do
              Map.put(acc_manifests, field, manifest)
            else
              acc_manifests
            end

          {new_data, new_manifests}

        _ ->
          {acc_data, acc_manifests}
      end
    end)
  end

  @spec redact_text(String.t(), keyword(), boolean()) :: {String.t(), map() | nil}
  defp redact_text(text, opts, true) do
    Redactor.redact_with_manifest(text, opts)
  end

  defp redact_text(text, opts, false) do
    {Redactor.redact(text, opts), nil}
  end

  @spec redact_nli_pairs(map(), keyword()) :: map()
  defp redact_nli_pairs(%{nli_pairs: pairs} = data, opts) when is_list(pairs) do
    redacted_pairs =
      Enum.map(pairs, fn pair ->
        pair
        |> Map.update(:premise, "", &Redactor.redact(&1, opts))
        |> Map.update(:hypothesis, "", &Redactor.redact(&1, opts))
      end)

    Map.put(data, :nli_pairs, redacted_pairs)
  end

  defp redact_nli_pairs(data, _opts), do: data

  @spec redact_claims(map(), keyword()) :: map()
  defp redact_claims(%{claims: claims} = data, opts) when is_list(claims) do
    redacted_claims =
      Enum.map(claims, fn claim ->
        Map.update(claim, :text, "", &Redactor.redact(&1, opts))
      end)

    data
    |> Map.put(:claims, redacted_claims)
    |> maybe_redact_source_claims(opts)
    |> maybe_redact_generated_claims(opts)
  end

  defp redact_claims(data, _opts), do: data

  @spec maybe_redact_source_claims(map(), keyword()) :: map()
  defp maybe_redact_source_claims(%{source_claims: claims} = data, opts) when is_list(claims) do
    redacted =
      Enum.map(claims, fn claim ->
        Map.update(claim, :text, "", &Redactor.redact(&1, opts))
      end)

    Map.put(data, :source_claims, redacted)
  end

  defp maybe_redact_source_claims(data, _opts), do: data

  @spec maybe_redact_generated_claims(map(), keyword()) :: map()
  defp maybe_redact_generated_claims(%{generated_claims: claims} = data, opts)
       when is_list(claims) do
    redacted =
      Enum.map(claims, fn claim ->
        Map.update(claim, :text, "", &Redactor.redact(&1, opts))
      end)

    Map.put(data, :generated_claims, redacted)
  end

  defp maybe_redact_generated_claims(data, _opts), do: data
end
