defmodule MedlumLlm.Labeling.Schemas do
  @moduledoc """
  Pre-built labeling schemas for medical NLP workflows.

  This module provides factory functions that return fully-configured
  `LabelingIR.Schema` structs for common medical labeling tasks:

  - **NLI Schema** - For human annotation of entailment/contradiction/neutral
  - **Clinical Verification Schema** - For overall document verification with domain accuracy
  - **Agent Verification Schema** - For CVL agent output with confidence scores

  ## Example

      iex> schema = MedlumLlm.Labeling.Schemas.nli_schema(tenant_id: "medlum")
      iex> schema.id
      "cvl_nli_schema_v1"
      iex> length(schema.fields)
      5

      iex> schema = MedlumLlm.Labeling.Schemas.clinical_verification_schema()
      iex> schema.id
      "cvl_clinical_verification_v1"

  """

  alias LabelingIR.Schema
  alias LabelingIR.Schema.Field

  @default_tenant "medlum"
  @default_namespace "cvl"

  @doc """
  NLI labeling schema for human annotators.

  Creates a schema with fields for:
  - `nli_label` - Required select field (ENTAILMENT, CONTRADICTION, NEUTRAL)
  - `confidence` - Required 1-5 scale for labeler confidence
  - `evidence_spans` - Optional text for quoted evidence from premise
  - `reasoning` - Optional text explanation
  - `difficulty` - Optional select (easy, medium, hard)

  ## Options

  - `:tenant_id` - Override default tenant (default: "medlum")
  - `:namespace` - Override default namespace (default: "cvl")
  - `:id` - Override schema ID (default: "cvl_nli_schema_v1")

  ## Examples

      iex> schema = MedlumLlm.Labeling.Schemas.nli_schema()
      iex> schema.tenant_id
      "medlum"

      iex> schema = MedlumLlm.Labeling.Schemas.nli_schema(tenant_id: "custom", namespace: "training")
      iex> schema.tenant_id
      "custom"
      iex> schema.namespace
      "training"

  """
  @spec nli_schema(keyword()) :: Schema.t()
  def nli_schema(opts \\ []) do
    tenant_id = Keyword.get(opts, :tenant_id, @default_tenant)
    namespace = Keyword.get(opts, :namespace, @default_namespace)
    id = Keyword.get(opts, :id, "cvl_nli_schema_v1")

    %Schema{
      id: id,
      tenant_id: tenant_id,
      namespace: namespace,
      fields: [
        %Field{
          name: "nli_label",
          type: :select,
          required: true,
          options: ["ENTAILMENT", "CONTRADICTION", "NEUTRAL"],
          help: "Does the hypothesis follow from, contradict, or neither the premise?"
        },
        %Field{
          name: "confidence",
          type: :scale,
          required: true,
          min: 1,
          max: 5,
          help: "How confident are you? (1=uncertain, 5=certain)"
        },
        %Field{
          name: "evidence_spans",
          type: :text,
          required: false,
          help: "Quote the relevant text from the premise that supports your label"
        },
        %Field{
          name: "reasoning",
          type: :text,
          required: false,
          help: "Explain your reasoning for this label"
        },
        %Field{
          name: "difficulty",
          type: :select,
          required: false,
          options: ["easy", "medium", "hard"],
          help: "How difficult was this example to label?"
        }
      ],
      layout: %{
        "primary_field" => "nli_label",
        "secondary_fields" => ["confidence", "evidence_spans"],
        "optional_fields" => ["reasoning", "difficulty"]
      },
      metadata: %{
        "version" => "1.0",
        "domain" => "medical_nli"
      }
    }
  end

  @doc """
  Clinical verification schema with domain accuracy fields.

  Creates a schema for comprehensive clinical document verification with:
  - `overall_verdict` - Required select (VERIFIED, HALLUCINATION, PARTIAL, UNCERTAIN)
  - `hallucinated_claims` - Optional text listing unsupported claims
  - `missing_critical_info` - Optional text listing missing critical information
  - `medication_accuracy` - Required 0-100 scale
  - `lab_accuracy` - Required 0-100 scale
  - `temporal_accuracy` - Required 0-100 scale

  ## Options

  - `:tenant_id` - Override default tenant (default: "medlum")
  - `:namespace` - Override default namespace (default: "cvl")
  - `:id` - Override schema ID (default: "cvl_clinical_verification_v1")

  ## Examples

      iex> schema = MedlumLlm.Labeling.Schemas.clinical_verification_schema()
      iex> schema.id
      "cvl_clinical_verification_v1"
      iex> Enum.find(schema.fields, & &1.name == "medication_accuracy").max
      100

  """
  @spec clinical_verification_schema(keyword()) :: Schema.t()
  def clinical_verification_schema(opts \\ []) do
    tenant_id = Keyword.get(opts, :tenant_id, @default_tenant)
    namespace = Keyword.get(opts, :namespace, @default_namespace)
    id = Keyword.get(opts, :id, "cvl_clinical_verification_v1")

    %Schema{
      id: id,
      tenant_id: tenant_id,
      namespace: namespace,
      fields: [
        %Field{
          name: "overall_verdict",
          type: :select,
          required: true,
          options: ["VERIFIED", "HALLUCINATION", "PARTIAL", "UNCERTAIN"],
          help: "Overall assessment of the generated summary"
        },
        %Field{
          name: "hallucinated_claims",
          type: :text,
          required: false,
          help: "List any claims that are not supported by source documents"
        },
        %Field{
          name: "missing_critical_info",
          type: :text,
          required: false,
          help: "List any critical information from sources that is missing"
        },
        %Field{
          name: "medication_accuracy",
          type: :scale,
          required: true,
          min: 0,
          max: 100,
          help: "Accuracy of medication information (0-100%)"
        },
        %Field{
          name: "lab_accuracy",
          type: :scale,
          required: true,
          min: 0,
          max: 100,
          help: "Accuracy of lab values (0-100%)"
        },
        %Field{
          name: "temporal_accuracy",
          type: :scale,
          required: true,
          min: 0,
          max: 100,
          help: "Accuracy of timeline and dates (0-100%)"
        }
      ],
      layout: %{
        "primary_field" => "overall_verdict",
        "accuracy_fields" => ["medication_accuracy", "lab_accuracy", "temporal_accuracy"],
        "detail_fields" => ["hallucinated_claims", "missing_critical_info"]
      },
      metadata: %{
        "version" => "1.0",
        "domain" => "clinical_verification"
      }
    }
  end

  @doc """
  Agent verification schema for CVL agents.

  Creates a schema for automated verification agent output with:
  - `verdict` - Required select (ENTAILMENT, CONTRADICTION, NEUTRAL, ABSTAIN)
  - `confidence` - Required 0-100 scale
  - `evidence` - Optional text for evidence strings
  - `ontology_codes` - Optional text for comma-separated ontology codes

  ## Options

  - `:tenant_id` - Override default tenant (default: "medlum")
  - `:namespace` - Override default namespace (default: "cvl")
  - `:id` - Override schema ID (default: "cvl_agent_verification_v1")

  ## Examples

      iex> schema = MedlumLlm.Labeling.Schemas.agent_verification_schema()
      iex> schema.id
      "cvl_agent_verification_v1"
      iex> verdict_field = Enum.find(schema.fields, & &1.name == "verdict")
      iex> "ABSTAIN" in verdict_field.options
      true

  """
  @spec agent_verification_schema(keyword()) :: Schema.t()
  def agent_verification_schema(opts \\ []) do
    tenant_id = Keyword.get(opts, :tenant_id, @default_tenant)
    namespace = Keyword.get(opts, :namespace, @default_namespace)
    id = Keyword.get(opts, :id, "cvl_agent_verification_v1")

    %Schema{
      id: id,
      tenant_id: tenant_id,
      namespace: namespace,
      fields: [
        %Field{
          name: "verdict",
          type: :select,
          required: true,
          options: ["ENTAILMENT", "CONTRADICTION", "NEUTRAL", "ABSTAIN"],
          help: "Agent's verification verdict"
        },
        %Field{
          name: "confidence",
          type: :scale,
          required: true,
          min: 0,
          max: 100,
          help: "Agent confidence score (0-100%)"
        },
        %Field{
          name: "evidence",
          type: :text,
          required: false,
          help: "Evidence strings supporting the verdict"
        },
        %Field{
          name: "ontology_codes",
          type: :text,
          required: false,
          help: "Comma-separated ontology codes supporting the verdict"
        }
      ],
      layout: %{
        "primary_field" => "verdict",
        "secondary_fields" => ["confidence"],
        "detail_fields" => ["evidence", "ontology_codes"]
      },
      metadata: %{
        "version" => "1.0",
        "domain" => "agent_verification"
      }
    }
  end

  @doc """
  Returns a list of all available schema factory function names.

  ## Examples

      iex> MedlumLlm.Labeling.Schemas.available_schemas()
      [:nli_schema, :clinical_verification_schema, :agent_verification_schema]

  """
  @spec available_schemas() :: [atom()]
  def available_schemas do
    [:nli_schema, :clinical_verification_schema, :agent_verification_schema]
  end
end
