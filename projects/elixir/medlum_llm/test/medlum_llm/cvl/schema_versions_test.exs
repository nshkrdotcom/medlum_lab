defmodule MedlumLlm.CVL.SchemaVersionsTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.CVL.SchemaVersions

  describe "current_version/0" do
    test "returns current schema version" do
      version = SchemaVersions.current_version()

      assert is_binary(version)
      assert version == "1.1"
    end
  end

  describe "available_versions/0" do
    test "returns list of available versions" do
      versions = SchemaVersions.available_versions()

      assert is_list(versions)
      assert "1.0" in versions
      assert "1.1" in versions
    end

    test "versions are sorted" do
      versions = SchemaVersions.available_versions()

      assert versions == Enum.sort(versions)
    end
  end

  describe "stable_versions/0" do
    test "returns only stable versions" do
      versions = SchemaVersions.stable_versions()

      assert is_list(versions)
      assert length(versions) >= 1
    end
  end

  describe "valid_version?/1" do
    test "returns true for valid versions" do
      assert SchemaVersions.valid_version?("1.0") == true
      assert SchemaVersions.valid_version?("1.1") == true
    end

    test "returns false for invalid versions" do
      assert SchemaVersions.valid_version?("9.9") == false
      assert SchemaVersions.valid_version?("invalid") == false
    end
  end

  describe "schema/1" do
    test "returns schema for version 1.0" do
      schema = SchemaVersions.schema("1.0")

      assert schema != nil
      assert schema.version == "1.0"
      assert schema.name == "cvl_nli_v1.0"
    end

    test "returns schema for version 1.1" do
      schema = SchemaVersions.schema("1.1")

      assert schema != nil
      assert schema.version == "1.1"
      assert schema.name == "cvl_nli_v1.1"
    end

    test "returns nil for invalid version" do
      assert SchemaVersions.schema("9.9") == nil
    end

    test "version 1.0 has fewer fields than 1.1" do
      schema_1_0 = SchemaVersions.schema("1.0")
      schema_1_1 = SchemaVersions.schema("1.1")

      assert length(schema_1_0.fields) < length(schema_1_1.fields)
    end
  end

  describe "schema_info/1" do
    test "returns info for valid version" do
      info = SchemaVersions.schema_info("1.0")

      assert info != nil
      assert info.name == "cvl_nli_v1.0"
      assert info.status == :stable
      assert %Date{} = info.released
    end

    test "returns nil for invalid version" do
      assert SchemaVersions.schema_info("9.9") == nil
    end

    test "info contains expected fields" do
      info = SchemaVersions.schema_info("1.1")

      assert Map.has_key?(info, :name)
      assert Map.has_key?(info, :released)
      assert Map.has_key?(info, :status)
      assert Map.has_key?(info, :fields)
      assert Map.has_key?(info, :description)
    end
  end

  describe "field_mapping/2" do
    test "shows fields added between versions" do
      mapping = SchemaVersions.field_mapping("1.0", "1.1")

      assert is_map(mapping)
      assert mapping.from_version == "1.0"
      assert mapping.to_version == "1.1"
      assert :evidence_quality in mapping.added
      assert :reasoning in mapping.added
    end

    test "shows unchanged fields" do
      mapping = SchemaVersions.field_mapping("1.0", "1.1")

      assert :verdict in mapping.unchanged
      assert :confidence in mapping.unchanged
    end

    test "shows no removed fields for 1.0 to 1.1" do
      mapping = SchemaVersions.field_mapping("1.0", "1.1")

      assert mapping.removed == []
    end

    test "returns error for invalid version" do
      result = SchemaVersions.field_mapping("1.0", "9.9")

      assert {:error, :invalid_version} = result
    end
  end

  describe "validate_label/2" do
    test "validates correct label for version 1.0" do
      label = %{
        "verdict" => "ENTAILMENT",
        "confidence" => 4
      }

      assert :ok = SchemaVersions.validate_label(label, "1.0")
    end

    test "validates correct label for version 1.1" do
      label = %{
        "verdict" => "CONTRADICTION",
        "confidence" => 3,
        "evidence_quality" => "partial"
      }

      assert :ok = SchemaVersions.validate_label(label, "1.1")
    end

    test "returns error for invalid verdict" do
      label = %{
        "verdict" => "INVALID",
        "confidence" => 4
      }

      assert {:error, errors} = SchemaVersions.validate_label(label, "1.0")
      assert is_list(errors)
    end

    test "returns error for missing required field" do
      label = %{
        "verdict" => "ENTAILMENT"
        # missing confidence
      }

      assert {:error, errors} = SchemaVersions.validate_label(label, "1.0")
      assert Enum.any?(errors, fn e -> e.field == "confidence" end)
    end

    test "returns error for invalid version" do
      label = %{"verdict" => "ENTAILMENT", "confidence" => 4}

      assert {:error, :invalid_version} = SchemaVersions.validate_label(label, "9.9")
    end
  end

  describe "changelog/2" do
    test "returns changelog between versions" do
      changelog = SchemaVersions.changelog("1.0", "1.1")

      assert is_map(changelog)
      assert changelog.from.version == "1.0"
      assert changelog.to.version == "1.1"
      assert Map.has_key?(changelog, :changes)
    end

    test "includes release dates" do
      changelog = SchemaVersions.changelog("1.0", "1.1")

      assert %Date{} = changelog.from.released
      assert %Date{} = changelog.to.released
    end

    test "includes descriptions" do
      changelog = SchemaVersions.changelog("1.0", "1.1")

      assert is_binary(changelog.from.description)
      assert is_binary(changelog.to.description)
    end
  end
end
