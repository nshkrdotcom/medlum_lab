defmodule MedlumLlm.Integration.VersionCheckTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Integration.VersionCheck

  describe "check_library/1" do
    test "returns :ok for loaded libraries" do
      # Jason is always loaded as a dependency
      assert :ok = VersionCheck.check_library(:jason)
    end

    test "returns {:error, :not_loaded} for unloaded libraries" do
      assert {:error, :not_loaded} = VersionCheck.check_library(:nonexistent_library_xyz)
    end
  end

  describe "required_version/1" do
    test "returns version spec for known libraries" do
      assert "~> 0.1.5" = VersionCheck.required_version(:eval_ex)
      assert "~> 0.4.0" = VersionCheck.required_version(:crucible_bench)
    end

    test "returns nil for unknown libraries" do
      assert nil == VersionCheck.required_version(:unknown_lib)
    end
  end

  describe "required_libraries/0" do
    test "returns map of all required libraries" do
      libs = VersionCheck.required_libraries()

      assert is_map(libs)
      assert Map.has_key?(libs, :eval_ex)
      assert Map.has_key?(libs, :crucible_bench)
      assert Map.has_key?(libs, :crucible_harness)
      assert Map.has_key?(libs, :hf_datasets_ex)
      assert Map.has_key?(libs, :crucible_ensemble)
    end
  end

  describe "check_all/0" do
    # Note: This test may pass or fail depending on whether NSAI libraries
    # are actually installed. In CI, you might want to tag this as :integration
    test "returns :ok or {:error, errors}" do
      result = VersionCheck.check_all()

      case result do
        :ok ->
          assert true

        {:error, errors} ->
          assert is_list(errors)
          assert Enum.all?(errors, fn {lib, reason} -> is_atom(lib) and is_atom(reason) end)
      end
    end
  end
end
