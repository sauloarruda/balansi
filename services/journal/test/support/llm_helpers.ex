defmodule Journal.TestHelpers.LLMHelpers do
  @moduledoc """
  Test helpers for mocking OpenAI API responses in tests.

  Provides utilities to mock Req.post calls to OpenAI API and configure
  the OpenAI application environment for testing.

  These helpers are designed to work reliably with async tests by using
  process-local state and proper cleanup.

  ## Usage

      # In your test file
      alias Journal.TestHelpers.LLMHelpers

      test "processes meal with successful LLM response" do
        LLMHelpers.with_openai_mock(fn ->
          # Your test code that calls LLMService
        end)
      end

      # Or with custom response
      test "handles LLM error" do
        LLMHelpers.with_openai_mock_error({:error, :timeout}, fn ->
          # Your test code
        end)
      end
  """

  @openai_url "https://api.openai.com/v1/chat/completions"

  @doc """
  Default successful OpenAI API response for testing.

  Returns a valid OpenAI API response structure with nutritional estimation.
  """
  def default_openai_response do
    %{
      "choices" => [
        %{
          "message" => %{
            "content" => """
            {"protein_g": 25.5, "carbs_g": 45.0, "fat_g": 15.5, "calories_kcal": 450, "weight_g": 300, "comment": "Balanced meal with good nutritional value."}
            """
          }
        }
      ]
    }
  end

  @doc """
  Creates a custom OpenAI API response with specified nutritional values.

  ## Parameters
    - `protein_g`: Protein in grams (default: 25.5)
    - `carbs_g`: Carbs in grams (default: 45.0)
    - `fat_g`: Fat in grams (default: 15.5)
    - `calories_kcal`: Calories (default: 450)
    - `weight_g`: Weight in grams (default: 300)
    - `comment`: AI comment (default: "Balanced meal with good nutritional value.")

  ## Examples

      iex> response = LLMHelpers.create_openai_response(protein_g: 30.0, calories_kcal: 500)
      iex> response["choices"][0]["message"]["content"]
      # Contains JSON with protein_g: 30.0 and calories_kcal: 500
  """
  def create_openai_response(opts \\ []) do
    protein_g = Keyword.get(opts, :protein_g, 25.5)
    carbs_g = Keyword.get(opts, :carbs_g, 45.0)
    fat_g = Keyword.get(opts, :fat_g, 15.5)
    calories_kcal = Keyword.get(opts, :calories_kcal, 450)
    weight_g = Keyword.get(opts, :weight_g, 300)
    comment = Keyword.get(opts, :comment, "Balanced meal with good nutritional value.")

    json_content = Jason.encode!(%{
      "protein_g" => protein_g,
      "carbs_g" => carbs_g,
      "fat_g" => fat_g,
      "calories_kcal" => calories_kcal,
      "weight_g" => weight_g,
      "comment" => comment
    })

    %{
      "choices" => [
        %{
          "message" => %{
            "content" => json_content
          }
        }
      ]
    }
  end

  @doc """
  Sets up OpenAI API configuration for testing.

  Configures the application environment with a test API key.
  Uses persistent: false to ensure isolation between test processes.
  """
  def setup_openai_config do
    Application.put_env(:journal, :openai, [
      api_key: "test-api-key",
      model: "gpt-4o-mini"
    ], persistent: false)
  end

  @doc """
  Cleans up OpenAI API configuration after testing.
  """
  def cleanup_openai_config do
    Application.delete_env(:journal, :openai)
  end

  @doc """
  Executes a function with a mocked successful OpenAI API response.

  This function ensures proper isolation by:
  1. Saving the original configuration
  2. Setting up test configuration
  3. Creating a process-local mock
  4. Cleaning up after execution (even on failure)

  ## Parameters
    - `response`: Optional custom response (defaults to `default_openai_response/0`)
    - `fun`: Function to execute within the mock context

  ## Examples

      LLMHelpers.with_openai_mock(fn ->
        {:ok, estimation} = LLMService.estimate_meal("2 eggs")
        assert estimation.protein_g != nil
      end)

      # With custom response
      custom_response = LLMHelpers.create_openai_response(protein_g: 30.0)
      LLMHelpers.with_openai_mock(custom_response, fn ->
        {:ok, estimation} = LLMService.estimate_meal("chicken")
        assert Decimal.to_float(estimation.protein_g) == 30.0
      end)
  """
  def with_openai_mock(response \\ nil, fun) when is_function(fun, 0) do
    response = response || default_openai_response()

    with_mock_setup(fn ->
      create_mock_with_retry(fn ->
        :meck.expect(Req, :post, fn url, _opts ->
          if url == @openai_url do
            {:ok, %Req.Response{status: 200, body: response}}
          else
            :meck.passthrough([Req, :post, url, []])
          end
        end)
      end)

      fun.()
    end)
  end

  @doc """
  Executes a function with a mocked OpenAI API error response.

  ## Parameters
    - `error`: Error tuple to return, e.g., `{:error, :timeout}` or `{:error, {:api_error, 429, %{}}}`
    - `fun`: Function to execute within the mock context

  ## Examples

      LLMHelpers.with_openai_mock_error({:error, :timeout}, fn ->
        assert {:error, :timeout} = LLMService.estimate_meal("2 eggs")
      end)

      LLMHelpers.with_openai_mock_error({:error, {:api_error, 429, %{}}}, fn ->
        assert {:error, {:api_error, 429, _}} = LLMService.estimate_meal("2 eggs")
      end)
  """
  def with_openai_mock_error(error, fun) when is_function(fun, 0) do
    with_mock_setup(fn ->
      create_mock_with_retry(fn ->
        :meck.expect(Req, :post, fn url, _opts ->
          if url == @openai_url do
            case error do
              {:error, {:api_error, status, body}} ->
                {:ok, %Req.Response{status: status, body: body}}

              {:error, reason} ->
                {:error, reason}
            end
          else
            :meck.passthrough([Req, :post, url, []])
          end
        end)
      end)

      fun.()
    end)
  end

  @doc """
  Executes a function with OpenAI API key not configured.

  Useful for testing error handling when API key is missing.

  ## Examples

      LLMHelpers.with_openai_not_configured(fn ->
        assert {:error, :api_key_not_configured} = LLMService.estimate_meal("2 eggs")
      end)
  """
  def with_openai_not_configured(fun) when is_function(fun, 0) do
    original_config = Application.get_env(:journal, :openai)

    cleanup_openai_config()

    try do
      fun.()
    after
      restore_config(original_config)
    end
  end

  @doc """
  Executes a function with a mocked OpenAI API response that contains invalid JSON.

  Useful for testing JSON parsing error handling.

  ## Examples

      LLMHelpers.with_openai_invalid_json(fn ->
        assert {:error, {:parse_error, _}} = LLMService.estimate_meal("2 eggs")
      end)
  """
  def with_openai_invalid_json(fun) when is_function(fun, 0) do
    invalid_response = %{
      "choices" => [
        %{
          "message" => %{
            "content" => "This is not valid JSON"
          }
        }
      ]
    }

    with_openai_mock(invalid_response, fun)
  end

  @doc """
  Executes a function with a mocked OpenAI API response that has missing fields.

  Useful for testing error handling when required fields are missing.

  ## Examples

      LLMHelpers.with_openai_missing_fields(fn ->
        assert {:error, {:parse_error, _}} = LLMService.estimate_meal("2 eggs")
      end)
  """
  def with_openai_missing_fields(fun) when is_function(fun, 0) do
    incomplete_response = %{
      "choices" => [
        %{
          "message" => %{
            "content" => ~s({"protein_g": 25.5})
          }
        }
      ]
    }

    with_openai_mock(incomplete_response, fun)
  end

  # Private helper functions

  # Common setup/teardown logic for mock functions.
  # Handles lock acquisition, config setup, cleanup, and error handling.
  defp with_mock_setup(fun) do
    original_config = Application.get_env(:journal, :openai)

    # Acquire lock to prevent race conditions
    case Journal.TestHelpers.LLMLock.acquire() do
      :ok -> :ok
      {:error, :timeout} -> raise "Timeout acquiring LLM mock lock"
    end

    setup_openai_config()
    cleanup_mock_safely()

    try do
      fun.()
    after
      cleanup_mock_safely()
      restore_config(original_config)
      Journal.TestHelpers.LLMLock.release()
    end
  end

  # Retry is a safety net in case lock acquisition and mock creation
  # have a timing window where another process can create the mock.
  # The lock mechanism should prevent this, but the retry provides
  # additional resilience for edge cases in async test execution.
  defp create_mock_with_retry(setup_fun, retries \\ 3) do
    case :meck.new(Req, [:passthrough]) do
      :ok ->
        setup_fun.()
        :ok

      {:error, {:already_started, _}} when retries > 0 ->
        # Another process has the mock, wait and retry
        cleanup_mock_safely()
        :timer.sleep(5)
        create_mock_with_retry(setup_fun, retries - 1)

      error ->
        raise "Failed to create mock after retries: #{inspect(error)}"
    end
  end

  defp cleanup_mock_safely do
    try do
      if :meck.validate(Req) do
        :meck.unload(Req)
      end
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
    end
  end

  defp restore_config(nil) do
    cleanup_openai_config()
  end

  defp restore_config(config) do
    Application.put_env(:journal, :openai, config, persistent: false)
  end
end
