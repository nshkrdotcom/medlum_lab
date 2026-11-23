defmodule MedlumLlm.Guardrails do
  @moduledoc """
  LlmGuard integration for medical LLM applications.

  Provides pre-configured guardrail profiles for HIPAA-compliant clinical use cases:

  - HIPAA-compliant input/output validation
  - Clinical PII detection and redaction
  - Medical-context prompt injection prevention
  - Audit logging without PHI exposure

  ## Configuration Profiles

  - `config/1` - Standard clinical configuration
  - `export_config/1` - Aggressive mode for CVL training data export
  - `clinical_config/1` - Clinical-only patterns (no prompt injection checks)

  ## Usage with LlmGuard

      # Standard clinical validation
      config = MedlumLlm.Guardrails.config()

      case LlmGuard.validate_input(user_input, config) do
        {:ok, safe_input} -> process(safe_input)
        {:error, :detected, details} -> handle_blocked(details)
      end

      # For CVL training data export
      config = MedlumLlm.Guardrails.export_config(seed: "experiment_001")

  ## Example Flow

      # 1. Validate input
      {:ok, safe_input} = MedlumLlm.Guardrails.validate_input(user_text)

      # 2. Process with LLM
      response = MedlumLlm.Chat.generate(safe_input)

      # 3. Validate and redact output
      {:ok, safe_output} = MedlumLlm.Guardrails.validate_output(response)
  """

  alias MedlumLlm.Detectors.ClinicalPII
  alias MedlumLlm.Guardrails.Redactor

  @type config_opts :: [
          confidence_threshold: float(),
          include_tier_3: boolean(),
          redaction_strategy: :placeholder | :hash | :mask,
          date_shift_days: integer() | nil,
          seed: String.t() | nil,
          audit_enabled: boolean()
        ]

  @doc """
  Returns standard guardrails configuration for clinical use.

  Enables:
  - Prompt injection detection
  - Jailbreak detection
  - Clinical PII detection (Tier 1 + Tier 2)
  - Output validation

  ## Options

  - `:confidence_threshold` - Minimum confidence for detection (default: 0.7)
  - `:include_tier_3` - Include name/facility patterns (default: false)
  - `:redaction_strategy` - PII replacement style (default: :placeholder)
  - `:audit_enabled` - Enable audit logging (default: true)

  ## Examples

      config = MedlumLlm.Guardrails.config()
      config = MedlumLlm.Guardrails.config(confidence_threshold: 0.8)
  """
  @spec config(config_opts()) :: map()
  def config(opts \\ []) do
    %{
      # Security detectors
      prompt_injection_detection: true,
      jailbreak_detection: true,
      data_leakage_prevention: true,
      content_moderation: false,

      # Thresholds
      confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.7),
      max_input_length: 50_000,
      max_output_length: 50_000,

      # Custom detectors
      enabled_detectors: [ClinicalPII],

      # Caching
      caching: %{
        enabled: true,
        pattern_cache: true,
        result_cache: true,
        result_ttl_seconds: 600,
        max_cache_entries: 50_000
      },

      # Clinical-specific options
      custom_options: %{
        clinical_pii: %{
          include_tier_3: Keyword.get(opts, :include_tier_3, false),
          confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.7)
        },
        redaction: %{
          strategy: Keyword.get(opts, :redaction_strategy, :placeholder),
          date_shift_days: Keyword.get(opts, :date_shift_days),
          seed: Keyword.get(opts, :seed)
        },
        audit_enabled: Keyword.get(opts, :audit_enabled, true)
      }
    }
  end

  @doc """
  Returns aggressive configuration for CVL training data export.

  Optimized for maximum PHI recall:
  - Lower confidence threshold (0.5)
  - Includes Tier 3 patterns (names, facilities)
  - Deterministic redaction with seed

  ## Options

  - `:seed` - Seed for deterministic redaction (default: date-based)
  - `:confidence_threshold` - Minimum confidence (default: 0.5)

  ## Examples

      config = MedlumLlm.Guardrails.export_config(seed: "study_20260125")
  """
  @spec export_config(config_opts()) :: map()
  def export_config(opts \\ []) do
    seed = Keyword.get(opts, :seed, generate_export_seed())

    %{
      # Skip input validation for export
      prompt_injection_detection: false,
      jailbreak_detection: false,
      data_leakage_prevention: true,
      content_moderation: false,

      # Lower threshold for aggressive detection
      confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.5),
      max_input_length: 100_000,
      max_output_length: 100_000,

      # Custom detectors
      enabled_detectors: [ClinicalPII],

      # Caching
      caching: %{
        enabled: true,
        result_cache: true,
        result_ttl_seconds: 3600
      },

      # Aggressive clinical options
      custom_options: %{
        clinical_pii: %{
          include_tier_3: true,
          confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.5)
        },
        redaction: %{
          mode: :aggressive,
          strategy: :hash,
          seed: seed,
          preserve_temporal: true
        },
        safe_harbor_strict: true,
        audit_enabled: true
      }
    }
  end

  @doc """
  Returns clinical-only configuration (no prompt injection/jailbreak checks).

  Use when input source is trusted and only PII detection is needed.

  ## Options

  - `:confidence_threshold` - Minimum confidence (default: 0.7)
  - `:include_tier_3` - Include name/facility patterns (default: false)

  ## Examples

      config = MedlumLlm.Guardrails.clinical_config(include_tier_3: true)
  """
  @spec clinical_config(config_opts()) :: map()
  def clinical_config(opts \\ []) do
    %{
      prompt_injection_detection: false,
      jailbreak_detection: false,
      data_leakage_prevention: true,
      content_moderation: false,

      confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.7),
      max_input_length: 50_000,
      max_output_length: 50_000,

      enabled_detectors: [ClinicalPII],

      caching: %{
        enabled: true,
        result_cache: true,
        result_ttl_seconds: 600
      },

      custom_options: %{
        clinical_pii: %{
          include_tier_3: Keyword.get(opts, :include_tier_3, false),
          confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.7)
        },
        redaction: %{
          strategy: Keyword.get(opts, :redaction_strategy, :placeholder),
          seed: Keyword.get(opts, :seed)
        },
        audit_enabled: Keyword.get(opts, :audit_enabled, false)
      }
    }
  end

  @doc """
  Validates input text for clinical PII.

  Convenience wrapper that returns detection results without requiring
  full LlmGuard integration.

  ## Options

  - `:config` - Configuration map (default: standard config)
  - `:return_detections` - Include detection details (default: false)

  ## Returns

  - `{:ok, text}` - No PHI detected
  - `{:detected, result}` - PHI detected with details

  ## Examples

      case MedlumLlm.Guardrails.validate_input(text) do
        {:ok, _} -> :safe
        {:detected, result} -> handle_phi(result)
      end
  """
  @spec validate_input(String.t(), keyword()) :: {:ok, String.t()} | {:detected, map()}
  def validate_input(text, opts \\ []) do
    conf = Keyword.get(opts, :config, config())
    clinical_opts = get_in(conf, [:custom_options, :clinical_pii]) || %{}

    include_tier_3 = Map.get(clinical_opts, :include_tier_3, false)
    threshold = Map.get(clinical_opts, :confidence_threshold, 0.7)

    case ClinicalPII.detect(text, include_tier_3: include_tier_3, confidence_threshold: threshold) do
      {:safe, _} ->
        {:ok, text}

      {:detected, result} ->
        {:detected, result}
    end
  end

  @doc """
  Validates and optionally redacts output text.

  ## Options

  - `:config` - Configuration map (default: standard config)
  - `:redact` - Whether to apply redaction (default: true)
  - `:return_original_on_safe` - Return original text if safe (default: true)

  ## Returns

  - `{:ok, text}` - Safe (original or redacted)
  - `{:ok, redacted_text, manifest}` - Redacted with audit manifest

  ## Examples

      {:ok, safe_text} = MedlumLlm.Guardrails.validate_output(llm_response)
  """
  @spec validate_output(String.t(), keyword()) :: {:ok, String.t()} | {:ok, String.t(), map()}
  def validate_output(text, opts \\ []) do
    conf = Keyword.get(opts, :config, config())
    redact = Keyword.get(opts, :redact, true)
    return_original = Keyword.get(opts, :return_original_on_safe, true)

    clinical_opts = get_in(conf, [:custom_options, :clinical_pii]) || %{}
    redaction_opts = get_in(conf, [:custom_options, :redaction]) || %{}

    include_tier_3 = Map.get(clinical_opts, :include_tier_3, false)
    threshold = Map.get(clinical_opts, :confidence_threshold, 0.7)

    case ClinicalPII.detect(text, include_tier_3: include_tier_3, confidence_threshold: threshold) do
      {:safe, _} when return_original ->
        {:ok, text}

      {:safe, _} ->
        {:ok, text}

      {:detected, _} when redact ->
        mode =
          case Map.get(redaction_opts, :mode) do
            nil -> :automatic
            mode -> mode
          end

        strategy = Map.get(redaction_opts, :strategy, :placeholder)
        seed = Map.get(redaction_opts, :seed)

        {redacted, manifest} =
          Redactor.redact_with_manifest(text,
            mode: mode,
            replacement_style: strategy,
            seed: seed
          )

        {:ok, redacted, manifest}

      {:detected, result} ->
        {:detected, result}
    end
  end

  @doc """
  Convenience function for full input-output pipeline.

  Validates input, runs the provided function, then validates/redacts output.

  ## Examples

      result = MedlumLlm.Guardrails.pipeline(
        user_input,
        fn safe_input -> MedlumLlm.Chat.generate(safe_input) end
      )
  """
  @spec pipeline(String.t(), (String.t() -> String.t()), keyword()) ::
          {:ok, String.t()} | {:error, atom(), map()}
  def pipeline(input, process_fn, opts \\ []) do
    with {:ok, safe_input} <- validate_input(input, opts),
         output = process_fn.(safe_input),
         {:ok, safe_output} <- normalize_output(validate_output(output, opts)) do
      {:ok, safe_output}
    else
      {:detected, result} -> {:error, :phi_detected, result}
      {:error, reason, details} -> {:error, reason, details}
    end
  end

  # Private functions

  defp generate_export_seed do
    "export_" <> Date.to_iso8601(Date.utc_today())
  end

  defp normalize_output({:ok, text}), do: {:ok, text}
  defp normalize_output({:ok, text, _manifest}), do: {:ok, text}
  defp normalize_output({:detected, result}), do: {:detected, result}
end
