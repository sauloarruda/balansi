defmodule Journal.Helpers.DateHelperTest do
  use ExUnit.Case, async: true

  alias Journal.Helpers.DateHelper

  describe "normalize_to_date/1" do
    test "returns Date struct unchanged" do
      date = ~D[2024-01-15]
      assert DateHelper.normalize_to_date(date) == date
    end

    test "parses ISO8601 date strings" do
      result = DateHelper.normalize_to_date("2024-01-15")
      assert %Date{} = result
      assert result == ~D[2024-01-15]
    end

    test "defaults to today for nil" do
      result = DateHelper.normalize_to_date(nil)
      assert %Date{} = result
      assert result == Date.utc_today()
    end

    test "defaults to today for invalid date strings" do
      result = DateHelper.normalize_to_date("invalid-date")
      assert %Date{} = result
      assert result == Date.utc_today()
    end

    test "defaults to today for invalid date format" do
      result = DateHelper.normalize_to_date("2024-13-45")
      assert %Date{} = result
      assert result == Date.utc_today()
    end

    test "defaults to today for non-string, non-date values" do
      result = DateHelper.normalize_to_date(123)
      assert %Date{} = result
      assert result == Date.utc_today()
    end
  end

  describe "parse_iso8601/1" do
    test "parses valid ISO8601 date strings" do
      assert {:ok, ~D[2024-01-15]} = DateHelper.parse_iso8601("2024-01-15")
      assert {:ok, ~D[2023-12-31]} = DateHelper.parse_iso8601("2023-12-31")
    end

    test "returns error for invalid date strings" do
      assert {:error, :invalid_date} = DateHelper.parse_iso8601("invalid-date")
      assert {:error, :invalid_date} = DateHelper.parse_iso8601("2024-13-45")
      assert {:error, :invalid_date} = DateHelper.parse_iso8601("not-a-date")
    end

    test "returns error for non-string values" do
      assert {:error, :invalid_date} = DateHelper.parse_iso8601(nil)
      assert {:error, :invalid_date} = DateHelper.parse_iso8601(123)
      assert {:error, :invalid_date} = DateHelper.parse_iso8601(~D[2024-01-15])
    end
  end

  describe "normalize_date_from_attrs/1" do
    test "normalizes date from ISO8601 string" do
      attrs = %{"date" => "2024-01-15", "other" => "value"}
      result = DateHelper.normalize_date_from_attrs(attrs)

      assert result["date"] == ~D[2024-01-15]
      assert result["other"] == "value"
    end

    test "keeps Date struct unchanged" do
      date = ~D[2024-01-15]
      attrs = %{"date" => date, "other" => "value"}
      result = DateHelper.normalize_date_from_attrs(attrs)

      assert result["date"] == date
      assert result["other"] == "value"
    end

    test "adds today's date when date key is missing" do
      attrs = %{"other" => "value"}
      result = DateHelper.normalize_date_from_attrs(attrs)

      assert result["date"] == Date.utc_today()
      assert result["other"] == "value"
    end

    test "normalizes invalid date string to today" do
      attrs = %{"date" => "invalid-date", "other" => "value"}
      result = DateHelper.normalize_date_from_attrs(attrs)

      assert result["date"] == Date.utc_today()
      assert result["other"] == "value"
    end

    test "handles empty map" do
      result = DateHelper.normalize_date_from_attrs(%{})

      assert result["date"] == Date.utc_today()
    end

    test "handles non-string, non-Date date value" do
      attrs = %{"date" => 12345, "other" => "value"}
      result = DateHelper.normalize_date_from_attrs(attrs)

      assert result["date"] == Date.utc_today()
      assert result["other"] == "value"
    end

    test "handles atom date value" do
      attrs = %{"date" => :invalid, "other" => "value"}
      result = DateHelper.normalize_date_from_attrs(attrs)

      assert result["date"] == Date.utc_today()
      assert result["other"] == "value"
    end
  end
end
