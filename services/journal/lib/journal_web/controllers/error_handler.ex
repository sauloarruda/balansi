defmodule JournalWeb.ErrorHandler do
  @moduledoc """
  Centralized error handling for all controllers.

  Provides consistent error response formatting across the API,
  including meals, exercises, bioimpedance, and user profile controllers.

  ## Usage

      alias JournalWeb.ErrorHandler

      case SomeService.do_something() do
        {:ok, result} ->
          # handle success
        error ->
          ErrorHandler.handle_service_error(conn, error)
      end

  ## Supported Error Formats

  - `{:error, %Ecto.Changeset{}}` - Validation errors
  - `{:error, {:invalid_status, status, expected: expected_status}}` - Invalid status transitions
  - `{:error, :not_found}` - Resource not found
  - `{:error, reason}` when `reason` is a binary - Generic error messages
  - `{:error, reason}` - Catch-all for unexpected error formats
  """

  use JournalWeb, :controller

  @doc """
  Handles service layer errors and returns appropriate HTTP responses.

  ## Examples

      iex> conn = build_conn()
      iex> changeset = %Ecto.Changeset{errors: [meal_type: {"can't be blank", []}]}
      iex> ErrorHandler.handle_service_error(conn, {:error, changeset})
      # Returns conn with 422 status and errors JSON

      iex> conn = build_conn()
      iex> ErrorHandler.handle_service_error(conn, {:error, :not_found})
      # Returns conn with 404 status and error JSON
  """
  def handle_service_error(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: format_changeset_errors(changeset)})
  end

  def handle_service_error(conn, {:error, {:invalid_status, status, expected: expected_status}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Cannot process with status: #{status}. Expected: #{expected_status}"})
  end

  def handle_service_error(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Resource not found"})
  end

  def handle_service_error(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: reason})
  end

  def handle_service_error(conn, {:error, reason}) do
    # Catch-all for unexpected error formats
    require Logger
    Logger.error("Unexpected error format: #{inspect(reason)}")

    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "An unexpected error occurred"})
  end

  # Private functions

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        value_string = format_error_value(value)
        String.replace(acc, "%{#{key}}", value_string)
      end)
    end)
  end

  defp format_error_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_error_value(value) when is_binary(value), do: value
  defp format_error_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_error_value(value) when is_float(value), do: Float.to_string(value)
  defp format_error_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp format_error_value(%Date{} = d), do: Date.to_iso8601(d)
  defp format_error_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_error_value(value) when is_list(value), do: inspect(value)
  defp format_error_value(value), do: inspect(value)
end
