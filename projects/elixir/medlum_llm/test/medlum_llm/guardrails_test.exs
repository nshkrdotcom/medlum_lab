defmodule MedlumLlm.GuardrailsTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Detectors.ClinicalPII
  alias MedlumLlm.Guardrails

  describe "config/1" do
    test "returns config map with default settings" do
      config = Guardrails.config()

      assert is_map(config)
      assert config.prompt_injection_detection == true
      assert config.jailbreak_detection == true
      assert config.data_leakage_prevention == true
    end

    test "includes ClinicalPII in enabled_detectors" do
      config = Guardrails.config()

      assert ClinicalPII in config.enabled_detectors
    end

    test "sets default confidence threshold" do
      config = Guardrails.config()

      assert config.confidence_threshold == 0.7
    end

    test "accepts custom confidence threshold" do
      config = Guardrails.config(confidence_threshold: 0.85)

      assert config.confidence_threshold == 0.85
    end

    test "sets clinical_pii options" do
      config = Guardrails.config(include_tier_3: true)

      assert config.custom_options.clinical_pii.include_tier_3 == true
    end

    test "sets redaction options" do
      config = Guardrails.config(redaction_strategy: :hash, seed: "test_seed")

      assert config.custom_options.redaction.strategy == :hash
      assert config.custom_options.redaction.seed == "test_seed"
    end

    test "enables caching by default" do
      config = Guardrails.config()

      assert config.caching.enabled == true
    end

    test "enables audit by default" do
      config = Guardrails.config()

      assert config.custom_options.audit_enabled == true
    end
  end

  describe "export_config/1" do
    test "disables prompt injection and jailbreak detection" do
      config = Guardrails.export_config()

      assert config.prompt_injection_detection == false
      assert config.jailbreak_detection == false
    end

    test "uses lower confidence threshold" do
      config = Guardrails.export_config()

      assert config.confidence_threshold == 0.5
    end

    test "includes Tier 3 patterns" do
      config = Guardrails.export_config()

      assert config.custom_options.clinical_pii.include_tier_3 == true
    end

    test "uses hash redaction strategy" do
      config = Guardrails.export_config()

      assert config.custom_options.redaction.strategy == :hash
    end

    test "uses aggressive mode" do
      config = Guardrails.export_config()

      assert config.custom_options.redaction.mode == :aggressive
    end

    test "generates default seed if not provided" do
      config = Guardrails.export_config()

      assert is_binary(config.custom_options.redaction.seed)
      assert config.custom_options.redaction.seed =~ "export_"
    end

    test "accepts custom seed" do
      config = Guardrails.export_config(seed: "study_001")

      assert config.custom_options.redaction.seed == "study_001"
    end

    test "enables safe_harbor_strict mode" do
      config = Guardrails.export_config()

      assert config.custom_options.safe_harbor_strict == true
    end
  end

  describe "clinical_config/1" do
    test "disables prompt injection and jailbreak detection" do
      config = Guardrails.clinical_config()

      assert config.prompt_injection_detection == false
      assert config.jailbreak_detection == false
    end

    test "enables data_leakage_prevention" do
      config = Guardrails.clinical_config()

      assert config.data_leakage_prevention == true
    end

    test "uses default confidence threshold" do
      config = Guardrails.clinical_config()

      assert config.confidence_threshold == 0.7
    end

    test "excludes Tier 3 by default" do
      config = Guardrails.clinical_config()

      assert config.custom_options.clinical_pii.include_tier_3 == false
    end

    test "accepts include_tier_3 option" do
      config = Guardrails.clinical_config(include_tier_3: true)

      assert config.custom_options.clinical_pii.include_tier_3 == true
    end

    test "disables audit by default" do
      config = Guardrails.clinical_config()

      assert config.custom_options.audit_enabled == false
    end
  end

  describe "validate_input/2" do
    test "returns :ok for text without PHI" do
      text = "Patient presents with chest pain and shortness of breath."

      {:ok, result} = Guardrails.validate_input(text)

      assert result == text
    end

    test "returns :detected for text with PHI" do
      text = "Patient MRN: 12345678 presents with chest pain."

      {:detected, result} = Guardrails.validate_input(text)

      assert :mrn in result.patterns_matched
    end

    test "respects custom config" do
      text = "Dr. Smith examined the patient."

      # Default config (no Tier 3)
      {:ok, _} = Guardrails.validate_input(text)

      # With Tier 3 enabled
      config = Guardrails.config(include_tier_3: true, confidence_threshold: 0.5)
      {:detected, _} = Guardrails.validate_input(text, config: config)
    end
  end

  describe "validate_output/2" do
    test "returns :ok for text without PHI" do
      text = "The diagnosis is acute bronchitis."

      {:ok, result} = Guardrails.validate_output(text)

      assert result == text
    end

    test "redacts PHI when detected" do
      text = "Patient MRN: 12345678, DOB: 01/15/1980"

      {:ok, redacted, _manifest} = Guardrails.validate_output(text)

      assert redacted =~ "[MRN_REDACTED]"
      assert redacted =~ "[DOB_REDACTED]"
      refute redacted =~ "12345678"
    end

    test "returns manifest with redaction details" do
      text = "MRN: 12345678"

      {:ok, _redacted, manifest} = Guardrails.validate_output(text)

      assert manifest.redaction_count == 1
      assert manifest.redaction_types[:mrn] == 1
    end

    test "respects redact: false option" do
      text = "MRN: 12345678"

      {:detected, result} = Guardrails.validate_output(text, redact: false)

      assert :mrn in result.patterns_matched
    end
  end

  describe "pipeline/3" do
    test "validates input, processes, and validates output" do
      process_fn = fn input -> "Processed: #{input}" end

      {:ok, result} = Guardrails.pipeline("safe input", process_fn)

      assert result =~ "Processed: safe input"
    end

    test "blocks input with PHI" do
      process_fn = fn input -> "Processed: #{input}" end

      {:error, :phi_detected, _} = Guardrails.pipeline("MRN: 12345678", process_fn)
    end

    test "redacts PHI from output" do
      process_fn = fn _input -> "Response with MRN: 12345678" end

      {:ok, result} = Guardrails.pipeline("safe input", process_fn)

      assert result =~ "[MRN_REDACTED]"
      refute result =~ "12345678"
    end
  end

  describe "integration scenarios" do
    test "clinical workflow with safe input and output" do
      config = Guardrails.config()

      input = "What are the symptoms of diabetes?"
      {:ok, safe_input} = Guardrails.validate_input(input, config: config)

      # Simulate LLM response
      llm_response = "Common symptoms include increased thirst and frequent urination."
      {:ok, safe_output} = Guardrails.validate_output(llm_response, config: config)

      assert safe_input == input
      assert safe_output == llm_response
    end

    test "clinical workflow with PHI in output" do
      config = Guardrails.config()

      input = "Summarize the patient record."
      {:ok, safe_input} = Guardrails.validate_input(input, config: config)

      # Simulate LLM response with PHI
      llm_response = "Patient MRN: 12345678 was admitted with DOB: 01/15/1980"
      {:ok, safe_output, manifest} = Guardrails.validate_output(llm_response, config: config)

      assert safe_input == input
      assert safe_output =~ "[MRN_REDACTED]"
      assert safe_output =~ "[DOB_REDACTED]"
      assert manifest.redaction_count == 2
    end

    test "export workflow with aggressive redaction" do
      config = Guardrails.export_config(seed: "export_test")

      text = "Dr. Smith at Memorial Hospital treated MRN: 12345678"

      {:ok, redacted, manifest} = Guardrails.validate_output(text, config: config)

      # All identifiers should be redacted
      assert redacted =~ "[MRN_"
      assert redacted =~ "[PROVIDER_" or redacted =~ "[FACILITY_"
      assert manifest.redaction_count >= 1
    end
  end
end
