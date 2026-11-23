defmodule MedlumLlm.Labeling do
  @moduledoc """
  Medical-specific labeling extensions for MedlumLlm.

  This namespace provides types, validation, schemas, and builder functions
  for medical NLP workflows, specifically designed for MedlumLlm's Clinical
  Verification Layer (CVL) training data export.

  ## Module Overview

  ### Types and Validation

  - `MedlumLlm.Labeling.NLI` - NLI classification types and validation
  - `MedlumLlm.Labeling.CVL` - CVL multi-agent types and validation
  - `MedlumLlm.Labeling.ClinicalDocument` - Clinical document types
  - `MedlumLlm.Labeling.Metrics` - Standard medical metric keys

  ### Pre-built Schemas

  - `MedlumLlm.Labeling.Schemas` - NLI, clinical verification, and agent schemas

  ### Builder Functions

  - `MedlumLlm.Labeling.SampleBuilder` - Build samples for CVL workflows
  - `MedlumLlm.Labeling.LabelBuilder` - Build labels for CVL annotations

  ## Quick Start

      alias MedlumLlm.Labeling.{NLI, CVL, Schemas, SampleBuilder, LabelBuilder}

      # Create an NLI sample
      sample = SampleBuilder.build_nli_sample(
        "Patient is on metformin 500mg BID.",
        "Patient takes metformin 1000mg daily.",
        tenant_id: "medlum"
      )

      # Get the NLI labeling schema
      schema = Schemas.nli_schema(tenant_id: "medlum")

      # Create a human annotation label
      label = LabelBuilder.build_nli_label(%{
        assignment_id: "assign_001",
        sample_id: sample.id,
        queue_id: "cvl_queue",
        tenant_id: "medlum",
        user_id: "annotator_alice",
        verdict: :contradiction,
        time_spent_ms: 30_000,
        confidence: 5,
        reasoning: "Dose mismatch: 500mg BID vs 1000mg daily"
      })

  ## NLI Classification

  The Clinical Verification Layer uses 3-way Natural Language Inference:

  | Verdict | Label | CVL Meaning |
  |---------|-------|-------------|
  | `:entailment` | `"ENTAILMENT"` | Claim is verified by source |
  | `:contradiction` | `"CONTRADICTION"` | Hallucination detected |
  | `:neutral` | `"NEUTRAL"` | Insufficient evidence |

      # Convert between atoms and strings
      NLI.verdict_to_label(:entailment)     # => "ENTAILMENT"
      NLI.label_to_verdict("CONTRADICTION") # => {:ok, :contradiction}

  ## CVL Multi-Agent Verification

  CVL uses 5 specialized agents for consensus verification:

  1. `:medication` - Drug verification (RxNorm)
  2. `:lab` - Lab values (LOINC)
  3. `:ontology` - Clinical terminology (SNOMED-CT/ICD-10)
  4. `:temporal` - Timeline logic
  5. `:differential` - Diagnosis mapping

      # Validate an agent verdict
      verdict = %{
        verdict: :contradiction,
        confidence: 0.92,
        evidence: ["Dose mismatch"],
        ontology_codes: ["861004"]
      }
      {:ok, validated} = CVL.validate_agent_verdict(verdict)

      # Build agent label
      agent_label = LabelBuilder.build_agent_label(
        :medication,
        validated,
        assignment_id: "assign_001",
        sample_id: sample.id,
        queue_id: "agent_queue",
        tenant_id: "medlum",
        agent_id: "medication_agent_v1",
        time_spent_ms: 150
      )

  ## Clinical Documents

  Multi-document clinical context for verification:

      alias MedlumLlm.Labeling.ClinicalDocument

      documents = [
        %{
          type: :discharge_summary,
          content: "Patient discharged on metformin 500mg BID...",
          date: ~D[2026-01-15],
          provider_type: "endocrinology",
          ontology_codes: %{
            snomed_ct: ["44054006"],
            icd10: ["E11.9"],
            rxnorm: ["861004"],
            loinc: []
          }
        }
      ]

      sample = SampleBuilder.build_clinical_sample(
        documents,
        "Patient has well-controlled diabetes on metformin 1000mg daily.",
        claims: [%{"text" => "metformin 1000mg daily", "span" => [45, 67]}]
      )

  ## Pre-built Schemas

  Ready-to-use labeling schemas:

      # NLI human annotation
      nli_schema = Schemas.nli_schema(tenant_id: "medlum")

      # Clinical verification
      cv_schema = Schemas.clinical_verification_schema()

      # Agent verification
      agent_schema = Schemas.agent_verification_schema()

  ## Design Philosophy

  These extensions follow LabelingIR's design principles:

  1. **Non-invasive**: Uses existing `payload`, `values`, and `metadata` maps
  2. **Type-safe**: Provides type definitions and validation functions
  3. **Flexible**: All functions accept options for customization
  4. **Domain-agnostic core**: LabelingIR remains unchanged; medical
     specifics are isolated in this namespace
  """

  # Re-export common types and functions for convenience

  @doc """
  Convenience function to convert NLI verdict atom to string label.

  Delegates to `MedlumLlm.Labeling.NLI.verdict_to_label/1`.
  """
  @spec verdict_to_label(MedlumLlm.Labeling.NLI.verdict()) :: String.t()
  defdelegate verdict_to_label(verdict), to: MedlumLlm.Labeling.NLI

  @doc """
  Convenience function to parse NLI string label to verdict atom.

  Delegates to `MedlumLlm.Labeling.NLI.label_to_verdict/1`.
  """
  @spec label_to_verdict(String.t()) :: {:ok, MedlumLlm.Labeling.NLI.verdict()} | {:error, :invalid_label}
  defdelegate label_to_verdict(label), to: MedlumLlm.Labeling.NLI

  @doc """
  Returns the list of valid NLI label strings.

  Delegates to `MedlumLlm.Labeling.NLI.valid_labels/0`.
  """
  @spec valid_labels() :: [String.t()]
  defdelegate valid_labels(), to: MedlumLlm.Labeling.NLI

  @doc """
  Returns the list of CVL agent types.

  Delegates to `MedlumLlm.Labeling.CVL.agent_types/0`.
  """
  @spec agent_types() :: [MedlumLlm.Labeling.CVL.agent_type()]
  defdelegate agent_types(), to: MedlumLlm.Labeling.CVL

  @doc """
  Returns the list of clinical document types.

  Delegates to `MedlumLlm.Labeling.ClinicalDocument.document_types/0`.
  """
  @spec document_types() :: [MedlumLlm.Labeling.ClinicalDocument.document_type()]
  defdelegate document_types(), to: MedlumLlm.Labeling.ClinicalDocument

  @doc """
  Returns the list of CVL-specific metric keys.

  Delegates to `MedlumLlm.Labeling.Metrics.cvl_metric_keys/0`.
  """
  @spec cvl_metric_keys() :: [atom()]
  defdelegate cvl_metric_keys(), to: MedlumLlm.Labeling.Metrics
end
