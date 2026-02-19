defmodule Kerto.Interface.ValidateTest do
  use ExUnit.Case, async: true

  alias Kerto.Interface.Validate

  describe "relation/1" do
    test "accepts valid atom" do
      assert {:ok, :breaks} = Validate.relation(:breaks)
    end

    test "accepts valid string" do
      assert {:ok, :depends_on} = Validate.relation("depends_on")
    end

    test "rejects unknown atom" do
      assert {:error, _} = Validate.relation(:explodes)
    end

    test "rejects unknown string" do
      assert {:error, _} = Validate.relation("explodes")
    end
  end

  describe "node_kind/1" do
    test "accepts valid atom" do
      assert {:ok, :file} = Validate.node_kind(:file)
    end

    test "accepts valid string" do
      assert {:ok, :module} = Validate.node_kind("module")
    end

    test "rejects unknown kind" do
      assert {:error, _} = Validate.node_kind(:spaceship)
    end
  end

  describe "float_val/2" do
    test "accepts float" do
      assert {:ok, 0.5} = Validate.float_val(0.5, "factor")
    end

    test "coerces integer to float" do
      assert {:ok, 1.0} = Validate.float_val(1, "factor")
    end

    test "rejects string" do
      assert {:error, _} = Validate.float_val("abc", "factor")
    end

    test "rejects nil" do
      assert {:error, _} = Validate.float_val(nil, "factor")
    end
  end

  describe "integer_val/2" do
    test "accepts integer" do
      assert {:ok, 3} = Validate.integer_val(3, "depth")
    end

    test "rejects float" do
      assert {:error, _} = Validate.integer_val(3.5, "depth")
    end

    test "rejects string" do
      assert {:error, _} = Validate.integer_val("abc", "depth")
    end
  end
end
