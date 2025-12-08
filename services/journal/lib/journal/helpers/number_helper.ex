defmodule Journal.Helpers.NumberHelper do
  @moduledoc """
  Helper functions for normalizing and validating numeric values.

  This module provides utilities for converting various numeric types
  (strings, floats, integers, Decimals) to standardized formats (Decimal or integer)
  with proper validation and error handling.

  Used across meal entries, exercise logs, body measurements, and bioimpedance data.
  """

  @doc """
  Normalizes a value to a Decimal type.

  Validates the input before normalization and raises `ArgumentError` for invalid values.

  ## Parameters
    - `value` - The value to normalize (can be Decimal, string, float, integer, or nil)

  ## Returns
    - `%Decimal{}` - Normalized Decimal value
    - `nil` - If input is nil

  ## Examples

      iex> Journal.Helpers.NumberHelper.normalize_to_decimal("25.5")
      #Decimal<25.5>

      iex> Journal.Helpers.NumberHelper.normalize_to_decimal(25.5)
      #Decimal<25.5>

      iex> Journal.Helpers.NumberHelper.normalize_to_decimal(25)
      #Decimal<25>

      iex> Journal.Helpers.NumberHelper.normalize_to_decimal(nil)
      nil

  ## Raises
    - `ArgumentError` - If the value cannot be converted to a Decimal
  """
  def normalize_to_decimal(nil), do: nil
  def normalize_to_decimal(%Decimal{} = value), do: value

  def normalize_to_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> raise ArgumentError, "Cannot parse decimal from: #{inspect(value)}"
    end
  end

  def normalize_to_decimal(value) when is_float(value) do
    Decimal.from_float(value)
  end

  def normalize_to_decimal(value) when is_integer(value) do
    Decimal.new(value)
  end

  def normalize_to_decimal(value) do
    raise ArgumentError, "Invalid decimal value: #{inspect(value)}"
  end

  @doc """
  Normalizes a value to an integer type.

  Validates the input before normalization and raises `ArgumentError` for invalid values.

  ## Parameters
    - `value` - The value to normalize (can be integer, string, float, Decimal, or nil)

  ## Returns
    - `integer()` - Normalized integer value
    - `nil` - If input is nil

  ## Examples

      iex> Journal.Helpers.NumberHelper.normalize_to_integer("250")
      250

      iex> Journal.Helpers.NumberHelper.normalize_to_integer(250.7)
      250

      iex> Journal.Helpers.NumberHelper.normalize_to_integer(#Decimal<250>)
      250

      iex> Journal.Helpers.NumberHelper.normalize_to_integer(nil)
      nil

  ## Raises
    - `ArgumentError` - If the value cannot be converted to an integer
  """
  def normalize_to_integer(nil), do: nil
  def normalize_to_integer(value) when is_integer(value), do: value

  def normalize_to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> raise ArgumentError, "Cannot parse integer from: #{inspect(value)}"
    end
  end

  def normalize_to_integer(value) when is_float(value) do
    trunc(value)
  end

  def normalize_to_integer(%Decimal{} = value) do
    Decimal.to_integer(value)
  end

  def normalize_to_integer(value) do
    raise ArgumentError, "Invalid integer value: #{inspect(value)}"
  end

  @doc """
  Checks if a value is present (not nil and not empty string).

  Handles the case where 0 is a valid value (not falsy).

  ## Parameters
    - `value` - The value to check

  ## Returns
    - `true` - If value is present
    - `false` - If value is nil or empty string

  ## Examples

      iex> Journal.Helpers.NumberHelper.present?(0)
      true

      iex> Journal.Helpers.NumberHelper.present?(nil)
      false

      iex> Journal.Helpers.NumberHelper.present?("")
      false

      iex> Journal.Helpers.NumberHelper.present?(#Decimal<0>)
      true
  """
  def present?(nil), do: false
  def present?(""), do: false
  def present?(value) when is_number(value), do: true
  def present?(%Decimal{}), do: true
  def present?(value) when is_binary(value), do: true
  def present?(_), do: false

  @doc """
  Compares two values handling Decimal types correctly.

  ## Parameters
    - `a` - First value to compare
    - `b` - Second value to compare

  ## Returns
    - `true` - If values are different
    - `false` - If values are equal

  ## Examples

      iex> Journal.Helpers.NumberHelper.values_different?(#Decimal<25.5>, #Decimal<25.5>)
      false

      iex> Journal.Helpers.NumberHelper.values_different?(#Decimal<25.5>, 25.5)
      false

      iex> Journal.Helpers.NumberHelper.values_different?(25, #Decimal<25>)
      false

      iex> Journal.Helpers.NumberHelper.values_different?(nil, nil)
      false
  """
  def values_different?(nil, nil), do: false
  def values_different?(nil, _), do: true
  def values_different?(_, nil), do: true
  def values_different?(%Decimal{} = a, %Decimal{} = b), do: not Decimal.equal?(a, b)
  def values_different?(%Decimal{} = a, b) when is_number(b), do: not Decimal.equal?(a, normalize_to_decimal(b))
  def values_different?(a, %Decimal{} = b) when is_number(a), do: not Decimal.equal?(normalize_to_decimal(a), b)
  def values_different?(a, b), do: a != b
end
