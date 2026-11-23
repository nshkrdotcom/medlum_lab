defmodule MedlumLlm.CVL.ICD10StubTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.ICD10Stub

  describe "lookup/1" do
    test "finds type 2 diabetes" do
      assert {:ok, "E11.9"} = ICD10Stub.lookup("type 2 diabetes")
    end

    test "finds type 2 diabetes mellitus" do
      assert {:ok, "E11.9"} = ICD10Stub.lookup("type 2 diabetes mellitus")
    end

    test "finds type 1 diabetes" do
      assert {:ok, "E10.9"} = ICD10Stub.lookup("type 1 diabetes")
    end

    test "finds generic diabetes" do
      assert {:ok, "E14.9"} = ICD10Stub.lookup("diabetes")
    end

    test "finds hypertension" do
      assert {:ok, "I10"} = ICD10Stub.lookup("hypertension")
    end

    test "finds essential hypertension" do
      assert {:ok, "I10"} = ICD10Stub.lookup("essential hypertension")
    end

    test "finds heart attack" do
      assert {:ok, "I21.9"} = ICD10Stub.lookup("heart attack")
    end

    test "finds myocardial infarction" do
      assert {:ok, "I21.9"} = ICD10Stub.lookup("myocardial infarction")
    end

    test "finds MI abbreviation" do
      assert {:ok, "I21.9"} = ICD10Stub.lookup("mi")
    end

    test "finds pneumonia" do
      assert {:ok, "J18.9"} = ICD10Stub.lookup("pneumonia")
    end

    test "finds heart failure" do
      assert {:ok, "I50.9"} = ICD10Stub.lookup("heart failure")
    end

    test "finds congestive heart failure" do
      assert {:ok, "I50.9"} = ICD10Stub.lookup("congestive heart failure")
    end

    test "finds CHF abbreviation" do
      assert {:ok, "I50.9"} = ICD10Stub.lookup("chf")
    end

    test "finds chronic kidney disease" do
      assert {:ok, "N18.9"} = ICD10Stub.lookup("chronic kidney disease")
    end

    test "finds CKD abbreviation" do
      assert {:ok, "N18.9"} = ICD10Stub.lookup("ckd")
    end

    test "finds asthma" do
      assert {:ok, "J45.909"} = ICD10Stub.lookup("asthma")
    end

    test "finds COPD" do
      assert {:ok, "J44.9"} = ICD10Stub.lookup("copd")
    end

    test "finds atrial fibrillation" do
      assert {:ok, "I48.91"} = ICD10Stub.lookup("atrial fibrillation")
    end

    test "finds afib abbreviation" do
      assert {:ok, "I48.91"} = ICD10Stub.lookup("afib")
    end

    test "finds stroke" do
      assert {:ok, "I64"} = ICD10Stub.lookup("stroke")
    end

    test "finds CVA abbreviation" do
      assert {:ok, "I64"} = ICD10Stub.lookup("cva")
    end

    test "returns error for unknown term" do
      assert {:error, :not_found} = ICD10Stub.lookup("madeupitis")
    end

    test "normalizes case" do
      assert {:ok, "I10"} = ICD10Stub.lookup("HYPERTENSION")
      assert {:ok, "I10"} = ICD10Stub.lookup("Hypertension")
    end

    test "trims whitespace" do
      assert {:ok, "I10"} = ICD10Stub.lookup("  hypertension  ")
    end
  end

  describe "validate_code/1" do
    test "validates E11.9" do
      assert {:ok, info} = ICD10Stub.validate_code("E11.9")
      assert info.description =~ "Type 2 diabetes"
    end

    test "validates I10" do
      assert {:ok, info} = ICD10Stub.validate_code("I10")
      assert info.description =~ "hypertension"
    end

    test "validates I21.9" do
      assert {:ok, info} = ICD10Stub.validate_code("I21.9")
      assert info.description =~ "myocardial infarction"
    end

    test "validates J18.9" do
      assert {:ok, info} = ICD10Stub.validate_code("J18.9")
      assert info.description =~ "Pneumonia"
    end

    test "validates I50.9" do
      assert {:ok, info} = ICD10Stub.validate_code("I50.9")
      assert info.description =~ "Heart failure"
    end

    test "validates N18.9" do
      assert {:ok, info} = ICD10Stub.validate_code("N18.9")
      assert info.description =~ "Chronic kidney disease"
    end

    test "validates J45.909" do
      assert {:ok, info} = ICD10Stub.validate_code("J45.909")
      assert info.description =~ "asthma"
    end

    test "validates J44.9" do
      assert {:ok, info} = ICD10Stub.validate_code("J44.9")
      assert info.description =~ "Chronic obstructive pulmonary disease"
    end

    test "validates I48.91" do
      assert {:ok, info} = ICD10Stub.validate_code("I48.91")
      assert info.description =~ "atrial fibrillation"
    end

    test "validates I64" do
      assert {:ok, info} = ICD10Stub.validate_code("I64")
      assert info.description =~ "Stroke"
    end

    test "returns error for invalid code" do
      assert {:error, :invalid_code} = ICD10Stub.validate_code("ZZZ.99")
    end
  end

  describe "description/1" do
    test "returns description for E11.9" do
      assert {:ok, desc} = ICD10Stub.description("E11.9")
      assert desc == "Type 2 diabetes mellitus without complications"
    end

    test "returns description for I10" do
      assert {:ok, desc} = ICD10Stub.description("I10")
      assert desc == "Essential (primary) hypertension"
    end

    test "returns error for unknown code" do
      assert {:error, :not_found} = ICD10Stub.description("ZZZ.99")
    end
  end

  describe "chapter/1" do
    test "returns chapter for diabetes codes" do
      assert {:ok, "E00-E89"} = ICD10Stub.chapter("E11.9")
      assert {:ok, "E00-E89"} = ICD10Stub.chapter("E10.9")
    end

    test "returns chapter for cardiovascular codes" do
      assert {:ok, "I00-I99"} = ICD10Stub.chapter("I10")
      assert {:ok, "I00-I99"} = ICD10Stub.chapter("I21.9")
      assert {:ok, "I00-I99"} = ICD10Stub.chapter("I50.9")
    end

    test "returns chapter for respiratory codes" do
      assert {:ok, "J00-J99"} = ICD10Stub.chapter("J18.9")
      assert {:ok, "J00-J99"} = ICD10Stub.chapter("J45.909")
    end

    test "returns chapter for renal codes" do
      assert {:ok, "N00-N99"} = ICD10Stub.chapter("N18.9")
    end

    test "returns error for unknown code" do
      assert {:error, :not_found} = ICD10Stub.chapter("ZZZ.99")
    end
  end

  describe "category/1" do
    test "returns category for diabetes" do
      assert {:ok, "Diabetes mellitus"} = ICD10Stub.category("E11.9")
    end

    test "returns category for hypertension" do
      assert {:ok, "Hypertensive diseases"} = ICD10Stub.category("I10")
    end

    test "returns category for MI" do
      assert {:ok, "Ischemic heart diseases"} = ICD10Stub.category("I21.9")
    end

    test "returns category for heart failure" do
      assert {:ok, "Heart failure"} = ICD10Stub.category("I50.9")
    end

    test "returns error for unknown code" do
      assert {:error, :not_found} = ICD10Stub.category("ZZZ.99")
    end
  end

  describe "same_category?/2" do
    test "afib variants in same category" do
      assert ICD10Stub.same_category?("I48.91", "I48.0")
      assert ICD10Stub.same_category?("I48.0", "I48.1")
    end

    test "diabetes variants in same category" do
      assert ICD10Stub.same_category?("E11.9", "E10.9")
      assert ICD10Stub.same_category?("E10.9", "E14.9")
    end

    test "different categories return false" do
      refute ICD10Stub.same_category?("E11.9", "I10")
      refute ICD10Stub.same_category?("J18.9", "N18.9")
    end

    test "unknown codes return false" do
      refute ICD10Stub.same_category?("ZZZ.99", "I10")
      refute ICD10Stub.same_category?("I10", "ZZZ.99")
    end
  end

  describe "all_codes/0" do
    test "returns non-empty map" do
      codes = ICD10Stub.all_codes()
      assert is_map(codes)
      assert map_size(codes) > 0
    end

    test "all codes have description" do
      codes = ICD10Stub.all_codes()

      Enum.each(codes, fn {_code, info} ->
        assert Map.has_key?(info, :description)
      end)
    end

    test "all codes have chapter" do
      codes = ICD10Stub.all_codes()

      Enum.each(codes, fn {_code, info} ->
        assert Map.has_key?(info, :chapter)
      end)
    end

    test "all codes have category" do
      codes = ICD10Stub.all_codes()

      Enum.each(codes, fn {_code, info} ->
        assert Map.has_key?(info, :category)
      end)
    end
  end

  describe "all_terms/0" do
    test "returns non-empty map" do
      terms = ICD10Stub.all_terms()
      assert is_map(terms)
      assert map_size(terms) > 0
    end

    test "all terms map to valid codes" do
      terms = ICD10Stub.all_terms()
      codes = ICD10Stub.all_codes()

      Enum.each(terms, fn {_term, code} ->
        assert Map.has_key?(codes, code), "Term maps to invalid code: #{code}"
      end)
    end
  end
end
