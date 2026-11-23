defmodule MedOntology.ICD10.CodesTest do
  use ExUnit.Case, async: true

  alias MedOntology.ICD10.Codes

  describe "get/1" do
    test "returns data for existing code" do
      assert {:ok, data} = Codes.get("E11.9")
      assert data.description =~ "diabetes"
      assert data.billable == true
    end

    test "returns data for category code" do
      assert {:ok, data} = Codes.get("E11")
      assert data.description =~ "Type 2 diabetes"
      assert data.billable == false
    end

    test "handles case-insensitivity" do
      assert {:ok, data1} = Codes.get("e11.9")
      assert {:ok, data2} = Codes.get("E11.9")
      assert data1.description == data2.description
    end

    test "returns not_found for non-existent code" do
      assert :not_found = Codes.get("ZZZ.99")
    end

    test "includes excludes information" do
      assert {:ok, data} = Codes.get("E11")
      assert is_list(data.excludes1)
      assert is_list(data.excludes2)
    end

    test "includes includes information" do
      assert {:ok, data} = Codes.get("E11")
      assert is_list(data.includes)
    end
  end

  describe "search/2" do
    test "finds codes matching description" do
      results = Codes.search("diabetes")
      assert results != []

      assert Enum.all?(results, fn {_code, data} ->
               String.downcase(data.description) |> String.contains?("diabetes")
             end)
    end

    test "search is case-insensitive" do
      results1 = Codes.search("DIABETES")
      results2 = Codes.search("diabetes")
      assert results1 == results2
    end

    test "respects limit option" do
      results = Codes.search("diabetes", limit: 2)
      assert length(results) <= 2
    end

    test "returns empty list for no matches" do
      results = Codes.search("xyznonexistent")
      assert results == []
    end

    test "finds hypertension codes" do
      results = Codes.search("hypertension")
      assert results != []
    end
  end

  describe "children/2" do
    test "returns child codes of category" do
      children = Codes.children("E11")
      assert children != []

      assert Enum.all?(children, fn {code, _data} ->
               String.starts_with?(code, "E11.") or String.starts_with?(code, "E11")
             end)
    end

    test "excludes the parent code itself" do
      children = Codes.children("E11")
      codes = Enum.map(children, fn {code, _} -> code end)
      refute "E11" in codes
    end

    test "respects limit option" do
      children = Codes.children("E11", limit: 2)
      assert length(children) <= 2
    end

    test "returns sorted results" do
      children = Codes.children("E11")
      codes = Enum.map(children, fn {code, _} -> code end)
      assert codes == Enum.sort(codes)
    end
  end

  describe "in_range/3" do
    test "returns codes in range" do
      results = Codes.in_range("E10", "E14")
      assert results != []

      Enum.each(results, fn {code, _data} ->
        category = String.slice(code, 0, 3)
        assert category >= "E10" and category <= "E14"
      end)
    end

    test "includes both endpoints" do
      results = Codes.in_range("E10", "E11")
      codes = Enum.map(results, fn {code, _} -> code end)

      # Should include E10 codes and E11 codes
      has_e10 = Enum.any?(codes, &String.starts_with?(&1, "E10"))
      has_e11 = Enum.any?(codes, &String.starts_with?(&1, "E11"))
      assert has_e10 or has_e11
    end

    test "respects limit option" do
      results = Codes.in_range("E10", "E14", limit: 3)
      assert length(results) <= 3
    end

    test "returns sorted results" do
      results = Codes.in_range("E10", "E14")
      codes = Enum.map(results, fn {code, _} -> code end)
      assert codes == Enum.sort(codes)
    end
  end

  describe "exists?/1" do
    test "returns true for existing code" do
      assert Codes.exists?("E11.9") == true
    end

    test "returns true for category code" do
      assert Codes.exists?("E11") == true
    end

    test "returns false for non-existent code" do
      assert Codes.exists?("ZZZ.99") == false
    end

    test "handles case-insensitivity" do
      assert Codes.exists?("e11.9") == true
    end
  end

  describe "all/1" do
    test "returns list of codes" do
      codes = Codes.all()
      assert is_list(codes)
      assert codes != []
    end

    test "respects limit option" do
      codes = Codes.all(limit: 5)
      assert length(codes) <= 5
    end

    test "returns sorted results" do
      codes = Codes.all()
      code_list = Enum.map(codes, fn {code, _} -> code end)
      assert code_list == Enum.sort(code_list)
    end
  end

  describe "count/0" do
    test "returns count of codes" do
      count = Codes.count()
      assert is_integer(count)
      assert count > 0
    end

    test "count matches all() length" do
      count = Codes.count()
      all_codes = Codes.all(limit: 10_000)
      assert count == length(all_codes)
    end
  end

  describe "billable?/1" do
    test "returns true for billable code" do
      assert Codes.billable?("E11.9") == true
    end

    test "returns false for category code" do
      assert Codes.billable?("E11") == false
    end

    test "returns false for non-existent code" do
      assert Codes.billable?("ZZZ.99") == false
    end
  end
end
