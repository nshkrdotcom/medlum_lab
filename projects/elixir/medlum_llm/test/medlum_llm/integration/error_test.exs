defmodule MedlumLlm.Integration.ErrorTest do
  use ExUnit.Case, async: true

  alias MedlumLlm.Integration.Error

  describe "error struct" do
    test "creates error with all fields" do
      error = %Error{
        library: :hf_datasets_ex,
        operation: :load_dataset,
        reason: :not_found,
        context: %{dataset: :medqa}
      }

      assert error.library == :hf_datasets_ex
      assert error.operation == :load_dataset
      assert error.reason == :not_found
      assert error.context == %{dataset: :medqa}
    end
  end

  describe "message/1" do
    test "formats error message correctly" do
      error = %Error{
        library: :hf_datasets_ex,
        operation: :load_dataset,
        reason: :not_found,
        context: %{dataset: :medqa}
      }

      assert Exception.message(error) == "hf_datasets_ex.load_dataset failed: :not_found"
    end

    test "handles complex reason values" do
      error = %Error{
        library: :eval_ex,
        operation: :calculate,
        reason: {:missing_field, :predictions},
        context: %{}
      }

      assert Exception.message(error) ==
               "eval_ex.calculate failed: {:missing_field, :predictions}"
    end

    test "handles string reasons" do
      error = %Error{
        library: :crucible_bench,
        operation: :run,
        reason: "Connection timeout",
        context: %{}
      }

      assert Exception.message(error) == "crucible_bench.run failed: \"Connection timeout\""
    end
  end

  describe "raise/1" do
    test "can be raised as exception" do
      assert_raise Error, "test_lib.test_op failed: :test_reason", fn ->
        raise %Error{
          library: :test_lib,
          operation: :test_op,
          reason: :test_reason,
          context: %{}
        }
      end
    end
  end
end
