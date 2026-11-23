defmodule MedlumLlm.CVL.LabelingSchema do
  @moduledoc """
  CVL NLI labeling schema for human annotation via Anvil.

  Defines the schema structure for 3-way Natural Language Inference (NLI)
  classification tasks used to train the Clinical Verification Layer.

  ## Schema Fields

  - **verdict** - NLI classification label (required)
    - `ENTAILMENT`: The hypothesis is fully supported by the premise
    - `CONTRADICTION`: The hypothesis conflicts with information in the premise
    - `NEUTRAL`: The hypothesis is neither supported nor contradicted

  - **confidence** - Labeler confidence rating (required)
    - Scale: 1 (very uncertain) to 5 (very confident)

  - **evidence_quality** - Quality of evidence in premise (optional)
    - `clear`: Evidence clearly supports the judgment
    - `partial`: Some evidence available but incomplete
    - `ambiguous`: Evidence is unclear or contradictory
    - `missing`: Required information is absent from premise

  - **reasoning** - Brief explanation for classification (optional)
    - Free text field with PII redaction policy
    - Used for model error analysis and guideline refinement

  ## Schema Versions

  - `1.0`: Initial schema with verdict and confidence
  - `1.1`: Added evidence_quality assessment
  - `2.0`: Added reasoning field with evidence spans (future)

  ## Usage

      # Create default schema
      schema = MedlumLlm.CVL.LabelingSchema.schema()

      # Create schema without reasoning field
      schema = MedlumLlm.CVL.LabelingSchema.schema(include_reasoning: false)

      # Create schema with specific version
      schema = MedlumLlm.CVL.LabelingSchema.schema(version: "1.0")

      # Use with Anvil queue
      Anvil.create_queue(
        queue_id: "cvl_nli_training",
        schema: schema,
        policy: :redundancy,
        labels_per_sample: 3
      )
  """

  alias Anvil.Schema
  alias Anvil.Schema.Field

  @verdicts ["ENTAILMENT", "CONTRADICTION", "NEUTRAL"]
  @evidence_quality_options ["clear", "partial", "ambiguous", "missing"]

  @type schema_opts :: [
          version: String.t(),
          include_reasoning: boolean(),
          require_evidence_quality: boolean()
        ]

  @doc """
  Creates a new CVL NLI labeling schema.

  ## Options

  - `:version` - Schema version (default: "1.1")
  - `:include_reasoning` - Include optional reasoning field (default: true)
  - `:require_evidence_quality` - Make evidence_quality required (default: false)

  ## Examples

      iex> schema = MedlumLlm.CVL.LabelingSchema.schema()
      iex> schema.name
      "cvl_nli_v1.1"
      iex> length(schema.fields)
      4

      iex> schema = MedlumLlm.CVL.LabelingSchema.schema(include_reasoning: false)
      iex> length(schema.fields)
      3

      iex> schema = MedlumLlm.CVL.LabelingSchema.schema(version: "1.0")
      iex> schema.name
      "cvl_nli_v1.0"
  """
  @spec schema(schema_opts()) :: Schema.t()
  def schema(opts \\ []) do
    version = Keyword.get(opts, :version, "1.1")
    include_reasoning = Keyword.get(opts, :include_reasoning, true)
    require_evidence_quality = Keyword.get(opts, :require_evidence_quality, false)

    fields = build_fields(version, include_reasoning, require_evidence_quality)

    Schema.new(
      name: "cvl_nli_v#{version}",
      version: version,
      fields: fields,
      metadata: %{
        domain: :medical,
        task: :nli_classification,
        project: :cvl,
        guidelines_url: guidelines_url()
      }
    )
  end

  @doc """
  Returns the verdict field definition.

  This is the core NLI classification field with three options.
  """
  @spec verdict_field() :: Field.t()
  def verdict_field do
    %Field{
      name: "verdict",
      type: :select,
      required: true,
      options: @verdicts,
      description: verdict_description()
    }
  end

  @doc """
  Returns the confidence field definition.

  A 1-5 scale indicating labeler certainty in their judgment.
  """
  @spec confidence_field() :: Field.t()
  def confidence_field do
    %Field{
      name: "confidence",
      type: :range,
      required: true,
      min: 1,
      max: 5,
      description: confidence_description()
    }
  end

  @doc """
  Returns the evidence quality field definition.

  Assesses the quality of supporting evidence in the premise.
  """
  @spec evidence_quality_field(boolean()) :: Field.t()
  def evidence_quality_field(required \\ false) do
    %Field{
      name: "evidence_quality",
      type: :select,
      required: required,
      options: @evidence_quality_options,
      description: evidence_quality_description()
    }
  end

  @doc """
  Returns the reasoning field definition.

  Optional text explanation with PII protection metadata.
  """
  @spec reasoning_field() :: Field.t()
  def reasoning_field do
    %Field{
      name: "reasoning",
      type: :text,
      required: false,
      metadata: %{
        pii: :possible,
        retention_days: 365,
        redaction_policy: :regex_redact
      },
      description: reasoning_description()
    }
  end

  @doc """
  Returns all valid verdict options.
  """
  @spec verdicts() :: [String.t()]
  def verdicts, do: @verdicts

  @doc """
  Returns all valid evidence quality options.
  """
  @spec evidence_quality_options() :: [String.t()]
  def evidence_quality_options, do: @evidence_quality_options

  @doc """
  Returns the URL to labeling guidelines documentation.
  """
  @spec guidelines_url() :: String.t()
  def guidelines_url do
    "https://docs.medlum.ai/cvl/labeling-guidelines"
  end

  # Private helpers

  defp build_fields(version, include_reasoning, require_evidence_quality) do
    base_fields =
      case version do
        "1.0" ->
          [verdict_field(), confidence_field()]

        _ ->
          [
            verdict_field(),
            confidence_field(),
            evidence_quality_field(require_evidence_quality)
          ]
      end

    if include_reasoning do
      base_fields ++ [reasoning_field()]
    else
      base_fields
    end
  end

  defp verdict_description do
    """
    Select the NLI relationship between premise and hypothesis:

    ENTAILMENT: The hypothesis is fully supported by the premise.
    The information in the hypothesis can be inferred from or is
    consistent with the information in the premise.

    CONTRADICTION: The hypothesis conflicts with information in the premise.
    The hypothesis states something that directly contradicts what is
    stated or implied in the premise.

    NEUTRAL: The hypothesis is neither supported nor contradicted.
    The premise does not provide enough information to determine
    whether the hypothesis is true or false.
    """
  end

  defp confidence_description do
    """
    Rate your confidence in the verdict:

    1 - Very uncertain: Guessing, unclear evidence
    2 - Somewhat uncertain: Leaning toward answer but not sure
    3 - Moderately confident: Reasonable evidence but some doubt
    4 - Confident: Good evidence, minor uncertainty
    5 - Very confident: Clear evidence, high certainty
    """
  end

  defp evidence_quality_description do
    """
    Assess the quality of evidence in the premise:

    clear: Evidence clearly and unambiguously supports judgment
    partial: Some evidence available but incomplete or requires inference
    ambiguous: Evidence is unclear, contradictory, or open to interpretation
    missing: Required information to make judgment is absent from premise
    """
  end

  defp reasoning_description do
    """
    Optional: Briefly explain your classification (1-2 sentences).

    Helpful prompts:
    - What specific text in the premise led to your verdict?
    - What information would change your answer?
    - Any ambiguities or concerns about this sample?

    Note: Do NOT include any patient identifiable information.
    """
  end
end
