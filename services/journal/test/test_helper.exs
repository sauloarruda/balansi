ExUnit.start()

# Start the LLM lock agent for test isolation
case Journal.TestHelpers.LLMLock.start_link([]) do
  {:ok, _pid} -> :ok
  {:error, {:already_started, _pid}} -> :ok
  error -> raise "Failed to start LLMLock: #{inspect(error)}"
end

Ecto.Adapters.SQL.Sandbox.mode(Journal.Repo, :manual)
