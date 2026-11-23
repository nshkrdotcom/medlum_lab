defmodule MedlumLlm.CVL.LOINCStubTest do
  use ExUnit.Case

  alias MedlumLlm.CVL.LOINCStub

  describe "lookup/1" do
    test "finds known lab test by exact name" do
      assert {:ok, "4548-4"} = LOINCStub.lookup("hemoglobin_a1c")
      assert {:ok, "2345-7"} = LOINCStub.lookup("glucose")
      assert {:ok, "718-7"} = LOINCStub.lookup("hemoglobin")
      assert {:ok, "6690-2"} = LOINCStub.lookup("wbc")
      assert {:ok, "2160-0"} = LOINCStub.lookup("creatinine")
    end

    test "normalizes test names with spaces" do
      assert {:ok, "4548-4"} = LOINCStub.lookup("hemoglobin a1c")
    end

    test "normalizes test names with dashes" do
      assert {:ok, "4548-4"} = LOINCStub.lookup("hemoglobin-a1c")
    end

    test "is case insensitive" do
      assert {:ok, "4548-4"} = LOINCStub.lookup("HEMOGLOBIN_A1C")
      assert {:ok, "4548-4"} = LOINCStub.lookup("Hemoglobin_A1c")
    end

    test "returns error for unknown lab" do
      assert {:error, :not_found} = LOINCStub.lookup("unknown_test")
      assert {:error, :not_found} = LOINCStub.lookup("frobnicator")
    end

    test "supports all documented lab tests" do
      known_tests = [
        {"hemoglobin_a1c", "4548-4"},
        {"glucose", "2345-7"},
        {"hemoglobin", "718-7"},
        {"wbc", "6690-2"},
        {"creatinine", "2160-0"},
        {"bun", "3094-0"},
        {"potassium", "2823-3"},
        {"sodium", "2951-2"},
        {"platelets", "777-3"},
        {"inr", "6301-6"},
        {"egfr", "33914-3"},
        {"cholesterol_total", "2093-3"},
        {"ldl_cholesterol", "2089-1"},
        {"hdl_cholesterol", "2085-9"},
        {"tsh", "3016-3"}
      ]

      for {name, expected_loinc} <- known_tests do
        assert {:ok, ^expected_loinc} = LOINCStub.lookup(name),
               "Expected #{name} to have LOINC code #{expected_loinc}"
      end
    end
  end

  describe "reference_range/2" do
    test "returns range for known test" do
      {:ok, range} = LOINCStub.reference_range("4548-4")
      assert range.low == 4.0
      assert range.high == 5.6
      assert range.critical_low == 3.0
      assert range.critical_high == 14.0
    end

    test "returns glucose reference range" do
      {:ok, range} = LOINCStub.reference_range("2345-7")
      assert range.low == 70
      assert range.high == 100
    end

    test "returns hemoglobin reference range" do
      {:ok, range} = LOINCStub.reference_range("718-7")
      assert range.low == 12.0
      assert range.high == 17.5
    end

    test "returns error for unknown LOINC code" do
      assert {:error, :no_range_data} = LOINCStub.reference_range("99999-9")
    end

    test "accepts demographics parameter (for future use)" do
      {:ok, range} = LOINCStub.reference_range("4548-4", %{age: 55, sex: :female})
      # Currently ignores demographics, but accepts the parameter
      assert range.low == 4.0
    end
  end

  describe "physiological_limits/1" do
    test "returns limits for HbA1c" do
      {:ok, limits} = LOINCStub.physiological_limits("4548-4")
      assert limits.min == 2.0
      assert limits.max == 20.0
    end

    test "returns limits for glucose" do
      {:ok, limits} = LOINCStub.physiological_limits("2345-7")
      assert limits.min == 20
      assert limits.max == 600
    end

    test "returns limits for hemoglobin" do
      {:ok, limits} = LOINCStub.physiological_limits("718-7")
      assert limits.min == 3.0
      assert limits.max == 25.0
    end

    test "returns limits for potassium" do
      {:ok, limits} = LOINCStub.physiological_limits("2823-3")
      assert limits.min == 1.5
      assert limits.max == 10.0
    end

    test "returns limits for sodium" do
      {:ok, limits} = LOINCStub.physiological_limits("2951-2")
      assert limits.min == 100
      assert limits.max == 180
    end

    test "returns error for unknown LOINC code" do
      assert {:error, :no_limit_data} = LOINCStub.physiological_limits("99999-9")
    end
  end

  describe "expected_unit/1" do
    test "returns unit for HbA1c" do
      assert {:ok, "%"} = LOINCStub.expected_unit("4548-4")
    end

    test "returns unit for glucose" do
      assert {:ok, "mg/dL"} = LOINCStub.expected_unit("2345-7")
    end

    test "returns unit for hemoglobin" do
      assert {:ok, "g/dL"} = LOINCStub.expected_unit("718-7")
    end

    test "returns unit for WBC" do
      assert {:ok, "K/uL"} = LOINCStub.expected_unit("6690-2")
    end

    test "returns unit for potassium" do
      assert {:ok, "mEq/L"} = LOINCStub.expected_unit("2823-3")
    end

    test "returns unit for INR" do
      assert {:ok, "ratio"} = LOINCStub.expected_unit("6301-6")
    end

    test "returns unit for eGFR" do
      assert {:ok, "mL/min"} = LOINCStub.expected_unit("33914-3")
    end

    test "returns unit for TSH" do
      assert {:ok, "mIU/L"} = LOINCStub.expected_unit("3016-3")
    end

    test "returns error for unknown LOINC code" do
      assert {:error, :no_unit_data} = LOINCStub.expected_unit("99999-9")
    end
  end

  describe "critical values" do
    test "includes critical thresholds in reference range" do
      {:ok, range} = LOINCStub.reference_range("2823-3")
      # Potassium
      assert range.critical_low == 2.5
      assert range.critical_high == 6.5
    end

    test "handles nil critical values" do
      {:ok, range} = LOINCStub.reference_range("33914-3")
      # eGFR has critical_high: nil
      assert range.critical_low == 15
      assert is_nil(range.critical_high)
    end
  end
end
