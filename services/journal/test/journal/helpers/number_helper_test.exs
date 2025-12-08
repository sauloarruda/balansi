defmodule Journal.Helpers.NumberHelperTest do
  use ExUnit.Case, async: true

  alias Journal.Helpers.NumberHelper

  describe "normalize_to_decimal/1" do
    test "returns nil for nil input" do
      assert NumberHelper.normalize_to_decimal(nil) == nil
    end

    test "returns Decimal unchanged" do
      decimal = Decimal.new("25.5")
      assert NumberHelper.normalize_to_decimal(decimal) == decimal
    end

    test "converts string to Decimal" do
      result = NumberHelper.normalize_to_decimal("25.5")
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("25.5"))
    end

    test "converts float to Decimal" do
      result = NumberHelper.normalize_to_decimal(25.5)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("25.5"))
    end

    test "converts integer to Decimal" do
      result = NumberHelper.normalize_to_decimal(25)
      assert %Decimal{} = result
      assert Decimal.equal?(result, Decimal.new("25"))
    end

    test "raises ArgumentError for invalid string" do
      assert_raise ArgumentError, ~r/Cannot parse decimal/, fn ->
        NumberHelper.normalize_to_decimal("not a number")
      end
    end

    test "raises ArgumentError for invalid type" do
      assert_raise ArgumentError, ~r/Invalid decimal value/, fn ->
        NumberHelper.normalize_to_decimal([1, 2, 3])
      end
    end
  end

  describe "normalize_to_integer/1" do
    test "returns nil for nil input" do
      assert NumberHelper.normalize_to_integer(nil) == nil
    end

    test "returns integer unchanged" do
      assert NumberHelper.normalize_to_integer(250) == 250
    end

    test "converts string to integer" do
      assert NumberHelper.normalize_to_integer("250") == 250
    end

    test "converts float to integer (truncates)" do
      assert NumberHelper.normalize_to_integer(250.7) == 250
      assert NumberHelper.normalize_to_integer(250.2) == 250
    end

    test "converts Decimal to integer" do
      decimal = Decimal.new("250")
      assert NumberHelper.normalize_to_integer(decimal) == 250
    end

    test "raises ArgumentError for invalid string" do
      assert_raise ArgumentError, ~r/Cannot parse integer/, fn ->
        NumberHelper.normalize_to_integer("not a number")
      end
    end

    test "raises ArgumentError for invalid type" do
      assert_raise ArgumentError, ~r/Invalid integer value/, fn ->
        NumberHelper.normalize_to_integer([1, 2, 3])
      end
    end
  end

  describe "present?/1" do
    test "returns false for nil" do
      refute NumberHelper.present?(nil)
    end

    test "returns false for empty string" do
      refute NumberHelper.present?("")
    end

    test "returns true for zero" do
      assert NumberHelper.present?(0)
      assert NumberHelper.present?(0.0)
      assert NumberHelper.present?(Decimal.new("0"))
    end

    test "returns true for positive numbers" do
      assert NumberHelper.present?(1)
      assert NumberHelper.present?(25.5)
      assert NumberHelper.present?(Decimal.new("25.5"))
    end

    test "returns true for negative numbers" do
      assert NumberHelper.present?(-1)
      assert NumberHelper.present?(-25.5)
    end

    test "returns true for non-empty strings" do
      assert NumberHelper.present?("0")
      assert NumberHelper.present?("25.5")
      assert NumberHelper.present?("text")
    end

    test "returns false for other types" do
      refute NumberHelper.present?([1, 2, 3])
      refute NumberHelper.present?(%{a: 1})
    end
  end

  describe "values_different?/2" do
    test "returns false for two nils" do
      refute NumberHelper.values_different?(nil, nil)
    end

    test "returns true when one value is nil" do
      assert NumberHelper.values_different?(nil, 1)
      assert NumberHelper.values_different?(1, nil)
    end

    test "returns false for equal Decimals" do
      decimal = Decimal.new("25.5")
      refute NumberHelper.values_different?(decimal, decimal)
      refute NumberHelper.values_different?(Decimal.new("25.5"), Decimal.new("25.5"))
    end

    test "returns true for different Decimals" do
      assert NumberHelper.values_different?(Decimal.new("25.5"), Decimal.new("30.0"))
    end

    test "returns false for Decimal and equal number" do
      refute NumberHelper.values_different?(Decimal.new("25.5"), 25.5)
      refute NumberHelper.values_different?(25.5, Decimal.new("25.5"))
      refute NumberHelper.values_different?(Decimal.new("25"), 25)
      refute NumberHelper.values_different?(25, Decimal.new("25"))
    end

    test "returns true for Decimal and different number" do
      assert NumberHelper.values_different?(Decimal.new("25.5"), 30.0)
      assert NumberHelper.values_different?(30.0, Decimal.new("25.5"))
    end

    test "returns false for equal integers" do
      refute NumberHelper.values_different?(25, 25)
    end

    test "returns true for different integers" do
      assert NumberHelper.values_different?(25, 30)
    end

    test "returns false for equal strings" do
      refute NumberHelper.values_different?("test", "test")
    end

    test "returns true for different strings" do
      assert NumberHelper.values_different?("test", "other")
    end
  end
end
