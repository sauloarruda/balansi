defmodule Journal.TestHelpers.LLMLock do
  @moduledoc """
  Provides a process-safe lock for LLM mocks to prevent race conditions
  in async tests.

  This ensures that only one test using LLM mocks runs at a time,
  preventing conflicts when multiple tests try to mock Req simultaneously.
  """

  use Agent

  @agent_name __MODULE__

  def start_link(_opts) do
    Agent.start_link(fn -> :unlocked end, name: @agent_name)
  end

  @doc """
  Acquires the lock, waiting if necessary.
  Returns :ok when lock is acquired, or {:error, :timeout} if timeout is reached.
  """
  def acquire(timeout \\ 5000) do
    start_if_needed()

    case Agent.get_and_update(@agent_name, fn
      :unlocked -> {:ok, :locked}
      :locked -> {:wait, :locked}
    end) do
      :ok -> :ok
      :wait ->
        case wait_for_lock(timeout) do
          :ok -> :ok
          {:error, :timeout} -> {:error, :timeout}
        end
    end
  end

  @doc """
  Releases the lock.
  """
  def release do
    start_if_needed()
    Agent.update(@agent_name, fn _ -> :unlocked end)
  end

  defp wait_for_lock(timeout) do
    start_time = System.monotonic_time(:millisecond)

    wait_loop(start_time, timeout)
  end

  defp wait_loop(start_time, timeout) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= timeout do
      {:error, :timeout}
    else
      case Agent.get_and_update(@agent_name, fn
        :unlocked -> {:ok, :locked}
        :locked -> {:wait, :locked}
      end) do
        :ok -> :ok
        :wait ->
          Process.sleep(10)
          wait_loop(start_time, timeout)
      end
    end
  end

  defp start_if_needed do
    case Process.whereis(@agent_name) do
      nil ->
        case start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          error -> raise "Failed to start LLMLock: #{inspect(error)}"
        end
      _pid -> :ok
    end
  end
end
