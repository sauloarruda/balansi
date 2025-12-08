defmodule Journal.Helpers.DateHelper do
  @moduledoc """
  Helper functions for normalizing and parsing date values.

  This module provides utilities for converting various date formats
  (ISO8601 strings, Date structs) to standardized Date structs
  with proper validation and error handling.

  ## Function Selection

  - Use `normalize_to_date/1` when you want to default to today's date
    for invalid or missing values (e.g., user input with optional dates).

  - Use `parse_iso8601/1` when you need strict validation and want to
    handle invalid dates as errors (e.g., required API parameters).

  - Use `normalize_date_from_attrs/1` when extracting dates from
    attribute maps (e.g., form data, API request bodies).

  Used across meal entries and other date-based operations.
  """

  @doc """
  Normalizes a date value to a Date struct.

  Accepts ISO8601 date strings, Date structs, or nil.
  For invalid strings, defaults to today's date.

  ## Parameters
    - `value` - The value to normalize (can be Date struct, ISO8601 string, or nil)

  ## Returns
    - `%Date{}` - Normalized Date value
    - `Date.utc_today()` - If input is nil or invalid string

  ## Examples

      iex> Journal.Helpers.DateHelper.normalize_to_date("2024-01-15")
      ~D[2024-01-15]

      iex> Journal.Helpers.DateHelper.normalize_to_date(~D[2024-01-15])
      ~D[2024-01-15]

      iex> Journal.Helpers.DateHelper.normalize_to_date(nil)
      # Returns today's date (Date.utc_today())

      iex> Journal.Helpers.DateHelper.normalize_to_date("invalid-date")
      # Returns today's date (Date.utc_today())
  """
  def normalize_to_date(nil), do: Date.utc_today()
  def normalize_to_date(%Date{} = value), do: value

  def normalize_to_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> Date.utc_today()
    end
  end

  def normalize_to_date(_value) do
    Date.utc_today()
  end

  @doc """
  Parses an ISO8601 date string to a Date struct.

  Returns an error tuple for invalid dates instead of defaulting.

  ## Parameters
    - `date_string` - ISO8601 date string (e.g., "2024-01-15")

  ## Returns
    - `{:ok, %Date{}}` - On successful parse
    - `{:error, :invalid_date}` - If the string cannot be parsed

  ## Examples

      iex> Journal.Helpers.DateHelper.parse_iso8601("2024-01-15")
      {:ok, ~D[2024-01-15]}

      iex> Journal.Helpers.DateHelper.parse_iso8601("invalid-date")
      {:error, :invalid_date}

      iex> Journal.Helpers.DateHelper.parse_iso8601("2024-13-45")
      {:error, :invalid_date}
  """
  def parse_iso8601(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, :invalid_date}
    end
  end

  def parse_iso8601(_), do: {:error, :invalid_date}

  @doc """
  Extracts and normalizes a date from a map of attributes.

  Looks for a "date" key in the map and normalizes its value.
  If the key is missing or the value is invalid, defaults to today.

  ## Parameters
    - `attrs` - Map with optional "date" key (can be Date struct or ISO8601 string)

  ## Returns
    - Map with normalized "date" key

  ## Examples

      iex> Journal.Helpers.DateHelper.normalize_date_from_attrs(%{"date" => "2024-01-15"})
      %{"date" => ~D[2024-01-15]}

      iex> Journal.Helpers.DateHelper.normalize_date_from_attrs(%{"date" => ~D[2024-01-15]})
      %{"date" => ~D[2024-01-15]}

      iex> Journal.Helpers.DateHelper.normalize_date_from_attrs(%{})
      # Returns map with "date" key set to today's date (Date.utc_today())

      iex> Journal.Helpers.DateHelper.normalize_date_from_attrs(%{"date" => "invalid"})
      # Returns map with "date" key set to today's date (Date.utc_today())
  """
  def normalize_date_from_attrs(%{"date" => date} = attrs) when is_binary(date) do
    normalized_date = normalize_to_date(date)
    Map.put(attrs, "date", normalized_date)
  end

  def normalize_date_from_attrs(%{"date" => %Date{}} = attrs) do
    attrs
  end

  def normalize_date_from_attrs(%{"date" => _invalid} = attrs) do
    # Invalid date type, replace with today
    Map.put(attrs, "date", Date.utc_today())
  end

  def normalize_date_from_attrs(attrs) do
    Map.put_new(attrs, "date", Date.utc_today())
  end
end
