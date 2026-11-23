defmodule MedlumLlm.Labeling.SchemasTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Labeling.Schemas
  alias LabelingIR.Schema
  alias LabelingIR.Schema.Field

  describe "nli_schema/1" do
    test "returns valid Schema struct with defaults" do
      schema = Schemas.nli_schema()

      assert %Schema{} = schema
      assert schema.id == "cvl_nli_schema_v1"
      assert schema.tenant_id == "medlum"
      assert schema.namespace == "cvl"
    end

    test "accepts tenant_id override" do
      schema = Schemas.nli_schema(tenant_id: "custom_tenant")
      assert schema.tenant_id == "custom_tenant"
    end

    test "accepts namespace override" do
      schema = Schemas.nli_schema(namespace: "training")
      assert schema.namespace == "training"
    end

    test "accepts id override" do
      schema = Schemas.nli_schema(id: "custom_schema_id")
      assert schema.id == "custom_schema_id"
    end

    test "includes all required NLI fields" do
      schema = Schemas.nli_schema()
      field_names = Enum.map(schema.fields, & &1.name)

      assert "nli_label" in field_names
      assert "confidence" in field_names
      assert "evidence_spans" in field_names
      assert "reasoning" in field_names
      assert "difficulty" in field_names
    end

    test "nli_label field has correct configuration" do
      schema = Schemas.nli_schema()
      field = Enum.find(schema.fields, &(&1.name == "nli_label"))

      assert %Field{} = field
      assert field.type == :select
      assert field.required == true
      assert field.options == ["ENTAILMENT", "CONTRADICTION", "NEUTRAL"]
    end

    test "confidence field has correct range" do
      schema = Schemas.nli_schema()
      field = Enum.find(schema.fields, &(&1.name == "confidence"))

      assert field.type == :scale
      assert field.required == true
      assert field.min == 1
      assert field.max == 5
    end

    test "difficulty field has correct options" do
      schema = Schemas.nli_schema()
      field = Enum.find(schema.fields, &(&1.name == "difficulty"))

      assert field.type == :select
      assert field.required == false
      assert field.options == ["easy", "medium", "hard"]
    end

    test "includes layout configuration" do
      schema = Schemas.nli_schema()

      assert is_map(schema.layout)
      assert schema.layout["primary_field"] == "nli_label"
    end

    test "includes metadata" do
      schema = Schemas.nli_schema()

      assert schema.metadata["version"] == "1.0"
      assert schema.metadata["domain"] == "medical_nli"
    end
  end

  describe "clinical_verification_schema/1" do
    test "returns valid Schema struct with defaults" do
      schema = Schemas.clinical_verification_schema()

      assert %Schema{} = schema
      assert schema.id == "cvl_clinical_verification_v1"
      assert schema.tenant_id == "medlum"
    end

    test "includes all required fields" do
      schema = Schemas.clinical_verification_schema()
      field_names = Enum.map(schema.fields, & &1.name)

      assert "overall_verdict" in field_names
      assert "hallucinated_claims" in field_names
      assert "missing_critical_info" in field_names
      assert "medication_accuracy" in field_names
      assert "lab_accuracy" in field_names
      assert "temporal_accuracy" in field_names
    end

    test "overall_verdict field has correct options" do
      schema = Schemas.clinical_verification_schema()
      field = Enum.find(schema.fields, &(&1.name == "overall_verdict"))

      assert field.type == :select
      assert field.required == true
      assert field.options == ["VERIFIED", "HALLUCINATION", "PARTIAL", "UNCERTAIN"]
    end

    test "accuracy fields have 0-100 range" do
      schema = Schemas.clinical_verification_schema()

      for name <- ["medication_accuracy", "lab_accuracy", "temporal_accuracy"] do
        field = Enum.find(schema.fields, &(&1.name == name))
        assert field.type == :scale
        assert field.required == true
        assert field.min == 0
        assert field.max == 100
      end
    end
  end

  describe "agent_verification_schema/1" do
    test "returns valid Schema struct with defaults" do
      schema = Schemas.agent_verification_schema()

      assert %Schema{} = schema
      assert schema.id == "cvl_agent_verification_v1"
      assert schema.tenant_id == "medlum"
    end

    test "includes all required fields" do
      schema = Schemas.agent_verification_schema()
      field_names = Enum.map(schema.fields, & &1.name)

      assert "verdict" in field_names
      assert "confidence" in field_names
      assert "evidence" in field_names
      assert "ontology_codes" in field_names
    end

    test "verdict field includes ABSTAIN option" do
      schema = Schemas.agent_verification_schema()
      field = Enum.find(schema.fields, &(&1.name == "verdict"))

      assert field.type == :select
      assert "ABSTAIN" in field.options
    end

    test "confidence field has 0-100 range" do
      schema = Schemas.agent_verification_schema()
      field = Enum.find(schema.fields, &(&1.name == "confidence"))

      assert field.type == :scale
      assert field.min == 0
      assert field.max == 100
    end
  end

  describe "available_schemas/0" do
    test "returns list of schema function names" do
      schemas = Schemas.available_schemas()

      assert :nli_schema in schemas
      assert :clinical_verification_schema in schemas
      assert :agent_verification_schema in schemas
    end
  end

  describe "JSON serialization" do
    test "schemas can be serialized to JSON" do
      for schema_fn <- Schemas.available_schemas() do
        schema = apply(Schemas, schema_fn, [])
        assert {:ok, _json} = Jason.encode(schema)
      end
    end
  end
end
