defmodule MedlumLlm.CVL.LabelingSchemaTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.LabelingSchema
  alias Anvil.Schema

  describe "schema/1" do
    test "creates schema with default options" do
      schema = LabelingSchema.schema()

      assert schema.name == "cvl_nli_v1.1"
      assert schema.version == "1.1"
      assert schema.metadata.domain == :medical
      assert schema.metadata.task == :nli_classification
      assert schema.metadata.project == :cvl
    end

    test "creates schema with version 1.0" do
      schema = LabelingSchema.schema(version: "1.0")

      assert schema.name == "cvl_nli_v1.0"
      assert schema.version == "1.0"
      # Version 1.0 has only verdict and confidence
      assert length(schema.fields) == 2
    end

    test "creates schema without reasoning field" do
      schema = LabelingSchema.schema(include_reasoning: false)

      field_names = Enum.map(schema.fields, & &1.name)
      refute "reasoning" in field_names
    end

    test "creates schema with reasoning field by default" do
      schema = LabelingSchema.schema()

      field_names = Enum.map(schema.fields, & &1.name)
      assert "reasoning" in field_names
    end

    test "includes verdict, confidence, evidence_quality, and reasoning fields" do
      schema = LabelingSchema.schema()

      field_names = Enum.map(schema.fields, & &1.name)
      assert "verdict" in field_names
      assert "confidence" in field_names
      assert "evidence_quality" in field_names
      assert "reasoning" in field_names
    end
  end

  describe "verdict_field/0" do
    test "returns select field with correct options" do
      field = LabelingSchema.verdict_field()

      assert field.name == "verdict"
      assert field.type == :select
      assert field.required == true
      assert "ENTAILMENT" in field.options
      assert "CONTRADICTION" in field.options
      assert "NEUTRAL" in field.options
    end
  end

  describe "confidence_field/0" do
    test "returns range field with 1-5 bounds" do
      field = LabelingSchema.confidence_field()

      assert field.name == "confidence"
      assert field.type == :range
      assert field.required == true
      assert field.min == 1
      assert field.max == 5
    end
  end

  describe "evidence_quality_field/1" do
    test "returns select field with correct options" do
      field = LabelingSchema.evidence_quality_field()

      assert field.name == "evidence_quality"
      assert field.type == :select
      assert "clear" in field.options
      assert "partial" in field.options
      assert "ambiguous" in field.options
      assert "missing" in field.options
    end

    test "can be required or optional" do
      optional_field = LabelingSchema.evidence_quality_field(false)
      required_field = LabelingSchema.evidence_quality_field(true)

      assert optional_field.required == false
      assert required_field.required == true
    end
  end

  describe "reasoning_field/0" do
    test "returns text field with PII metadata" do
      field = LabelingSchema.reasoning_field()

      assert field.name == "reasoning"
      assert field.type == :text
      assert field.required == false
      assert field.metadata.pii == :possible
      assert field.metadata.retention_days == 365
      assert field.metadata.redaction_policy == :regex_redact
    end
  end

  describe "schema validation" do
    test "validates correct verdict values" do
      schema = LabelingSchema.schema()

      assert {:ok, _} =
               Schema.validate(schema, %{
                 "verdict" => "ENTAILMENT",
                 "confidence" => 4
               })

      assert {:ok, _} =
               Schema.validate(schema, %{
                 "verdict" => "CONTRADICTION",
                 "confidence" => 3
               })

      assert {:ok, _} =
               Schema.validate(schema, %{
                 "verdict" => "NEUTRAL",
                 "confidence" => 5
               })
    end

    test "rejects invalid verdict values" do
      schema = LabelingSchema.schema()

      assert {:error, errors} =
               Schema.validate(schema, %{
                 "verdict" => "INVALID",
                 "confidence" => 4
               })

      assert Enum.any?(errors, fn e -> e.field == "verdict" end)
    end

    test "validates confidence range" do
      schema = LabelingSchema.schema()

      # Valid confidence values
      for confidence <- 1..5 do
        assert {:ok, _} =
                 Schema.validate(schema, %{
                   "verdict" => "NEUTRAL",
                   "confidence" => confidence
                 })
      end
    end

    test "rejects confidence outside range" do
      schema = LabelingSchema.schema()

      assert {:error, errors} =
               Schema.validate(schema, %{
                 "verdict" => "NEUTRAL",
                 "confidence" => 0
               })

      assert Enum.any?(errors, fn e -> e.field == "confidence" end)

      assert {:error, errors} =
               Schema.validate(schema, %{
                 "verdict" => "NEUTRAL",
                 "confidence" => 6
               })

      assert Enum.any?(errors, fn e -> e.field == "confidence" end)
    end

    test "requires verdict field" do
      schema = LabelingSchema.schema()

      assert {:error, errors} =
               Schema.validate(schema, %{
                 "confidence" => 4
               })

      assert Enum.any?(errors, fn e -> e.field == "verdict" && e.error == "is required" end)
    end

    test "requires confidence field" do
      schema = LabelingSchema.schema()

      assert {:error, errors} =
               Schema.validate(schema, %{
                 "verdict" => "ENTAILMENT"
               })

      assert Enum.any?(errors, fn e -> e.field == "confidence" && e.error == "is required" end)
    end

    test "allows optional evidence_quality" do
      schema = LabelingSchema.schema()

      assert {:ok, _} =
               Schema.validate(schema, %{
                 "verdict" => "ENTAILMENT",
                 "confidence" => 4,
                 "evidence_quality" => "clear"
               })

      # Also valid without evidence_quality
      assert {:ok, _} =
               Schema.validate(schema, %{
                 "verdict" => "ENTAILMENT",
                 "confidence" => 4
               })
    end

    test "validates evidence_quality options" do
      schema = LabelingSchema.schema()

      assert {:error, errors} =
               Schema.validate(schema, %{
                 "verdict" => "ENTAILMENT",
                 "confidence" => 4,
                 "evidence_quality" => "invalid_option"
               })

      assert Enum.any?(errors, fn e -> e.field == "evidence_quality" end)
    end

    test "allows optional reasoning" do
      schema = LabelingSchema.schema()

      assert {:ok, _} =
               Schema.validate(schema, %{
                 "verdict" => "ENTAILMENT",
                 "confidence" => 4,
                 "reasoning" => "The premise clearly states the patient has diabetes"
               })
    end
  end

  describe "verdicts/0" do
    test "returns all valid verdict options" do
      verdicts = LabelingSchema.verdicts()

      assert "ENTAILMENT" in verdicts
      assert "CONTRADICTION" in verdicts
      assert "NEUTRAL" in verdicts
      assert length(verdicts) == 3
    end
  end

  describe "evidence_quality_options/0" do
    test "returns all valid evidence quality options" do
      options = LabelingSchema.evidence_quality_options()

      assert "clear" in options
      assert "partial" in options
      assert "ambiguous" in options
      assert "missing" in options
      assert length(options) == 4
    end
  end

  describe "guidelines_url/0" do
    test "returns documentation URL" do
      url = LabelingSchema.guidelines_url()

      assert is_binary(url)
      assert String.starts_with?(url, "https://")
    end
  end
end
