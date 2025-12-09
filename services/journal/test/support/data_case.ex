defmodule Journal.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Journal.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Journal.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Journal.DataCase
    end
  end

  setup tags do
    Journal.DataCase.setup_sandbox(tags)
    # Ensure default test patients exist (required for foreign key constraints)
    Journal.DataCase.ensure_test_patients()
    :ok
  end

  @doc """
  Ensures that default test patients (1 and 999) exist in the database.
  This is necessary because meal_entries have a foreign key constraint on patient_id.
  Creates associated users if they don't exist.
  """
  def ensure_test_patients do
    # Ensure patient 1 (POC patient)
    ensure_patient(1)
    # Ensure patient 999 (other patient)
    ensure_patient(999)
  end

  defp ensure_patient(patient_id) do
    # Check if patient exists
    result = Journal.Repo.query!("SELECT id FROM patients WHERE id = $1", [patient_id])
    
    if length(result.rows) == 0 do
      # Patient doesn't exist, create it along with required user
      user_id = patient_id
      
      # Ensure user exists
      user_result = Journal.Repo.query!("SELECT id FROM users WHERE id = $1", [user_id])
      if length(user_result.rows) == 0 do
        # Create user
        Journal.Repo.query!("""
          INSERT INTO users (id, name, email, cognito_id, inserted_at, updated_at)
          VALUES ($1, $2, $3, $4, NOW(), NOW())
        """, [user_id, "Test User #{user_id}", "test#{user_id}@example.com", "cognito-#{user_id}"])
      end
      
      # Create patient
      Journal.Repo.query!("""
        INSERT INTO patients (id, user_id, professional_id, inserted_at, updated_at)
        VALUES ($1, $2, $3, NOW(), NOW())
      """, [patient_id, user_id, 1])
    end
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Journal.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
