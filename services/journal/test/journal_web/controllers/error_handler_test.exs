defmodule JournalWeb.ErrorHandlerTest do
  @moduledoc """
  Unit tests for ErrorHandler module.

  Tests verify that all error formats are properly handled and
  return appropriate HTTP status codes and response formats.
  """
  use ExUnit.Case, async: true
  use JournalWeb.ConnCase

  alias JournalWeb.ErrorHandler
  alias Ecto.Changeset

  describe "handle_service_error/2" do
    test "handles changeset errors" do
      changeset = %Changeset{
        errors: [meal_type: {"can't be blank", []}],
        valid?: false
      }
      conn = build_conn()

      conn = ErrorHandler.handle_service_error(conn, {:error, changeset})

      assert conn.status == 422
      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["meal_type"] != nil
      assert is_list(errors["meal_type"])
    end

    test "handles changeset with multiple errors" do
      changeset = %Changeset{
        errors: [
          meal_type: {"can't be blank", []},
          original_description: {"can't be blank", []}
        ],
        valid?: false
      }
      conn = build_conn()

      conn = ErrorHandler.handle_service_error(conn, {:error, changeset})

      assert conn.status == 422
      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["meal_type"] != nil
      assert errors["original_description"] != nil
    end

    test "handles invalid_status errors" do
      conn = build_conn()
      conn = ErrorHandler.handle_service_error(conn, {:error, {:invalid_status, :pending, expected: :in_review}})

      assert conn.status == 422
      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "Cannot process with status: pending"
      assert error =~ "Expected: in_review"
    end

    test "handles not_found errors" do
      conn = build_conn()
      conn = ErrorHandler.handle_service_error(conn, {:error, :not_found})

      assert conn.status == 404
      assert %{"error" => "Resource not found"} = json_response(conn, 404)
    end

    test "handles string error messages" do
      conn = build_conn()
      conn = ErrorHandler.handle_service_error(conn, {:error, "Custom error message"})

      assert conn.status == 422
      assert %{"error" => "Custom error message"} = json_response(conn, 422)
    end

    test "handles unexpected error formats with catch-all" do
      conn = build_conn()
      conn = ErrorHandler.handle_service_error(conn, {:error, %{unexpected: "format"}})

      assert conn.status == 500
      assert %{"error" => "An unexpected error occurred"} = json_response(conn, 500)
    end

    test "handles atom error reasons" do
      conn = build_conn()
      conn = ErrorHandler.handle_service_error(conn, {:error, :database_error})

      assert conn.status == 500
      assert %{"error" => "An unexpected error occurred"} = json_response(conn, 500)
    end

    test "handles tuple error reasons" do
      conn = build_conn()
      conn = ErrorHandler.handle_service_error(conn, {:error, {:timeout, 5000}})

      assert conn.status == 500
      assert %{"error" => "An unexpected error occurred"} = json_response(conn, 500)
    end
  end
end
