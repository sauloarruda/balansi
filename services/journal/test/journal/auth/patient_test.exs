defmodule Journal.Auth.PatientTest do
  use ExUnit.Case, async: true
  use Journal.DataCase

  alias Journal.Auth.Patient
  alias Journal.Auth.User

  # Helper function to create unique user attributes for testing
  # Uses timestamp + unique integer to ensure uniqueness across test runs
  defp unique_user_attrs(overrides \\ %{}) do
    timestamp = System.system_time(:second)
    unique_id = System.unique_integer([:positive])
    Map.merge(%{
      name: "Test User",
      email: "test-#{timestamp}-#{unique_id}@example.com",
      cognito_id: "cognito-#{timestamp}-#{unique_id}"
    }, overrides)
  end

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        user_id: 1,
        professional_id: 1
      }

      changeset = Patient.changeset(%Patient{}, attrs)

      assert changeset.valid?
      assert changeset.changes.user_id == 1
      assert changeset.changes.professional_id == 1
    end

    test "invalid when required fields are missing" do
      attrs = %{}

      changeset = Patient.changeset(%Patient{}, attrs)

      refute changeset.valid?
      assert %{user_id: ["can't be blank"], professional_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when user_id is zero" do
      attrs = %{
        user_id: 0,
        professional_id: 1
      }

      changeset = Patient.changeset(%Patient{}, attrs)

      refute changeset.valid?
      assert %{user_id: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "invalid when user_id is negative" do
      attrs = %{
        user_id: -1,
        professional_id: 1
      }

      changeset = Patient.changeset(%Patient{}, attrs)

      refute changeset.valid?
      assert %{user_id: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "invalid when professional_id is zero" do
      attrs = %{
        user_id: 1,
        professional_id: 0
      }

      changeset = Patient.changeset(%Patient{}, attrs)

      refute changeset.valid?
      assert %{professional_id: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "invalid when professional_id is negative" do
      attrs = %{
        user_id: 1,
        professional_id: -1
      }

      changeset = Patient.changeset(%Patient{}, attrs)

      refute changeset.valid?
      assert %{professional_id: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "valid when user_id and professional_id are positive" do
      attrs = %{
        user_id: 1,
        professional_id: 1
      }

      changeset = Patient.changeset(%Patient{}, attrs)

      assert changeset.valid?
    end
  end

  describe "database operations" do
    setup do
      # Create a user for testing with unique identifiers to avoid conflicts
      user_attrs = unique_user_attrs()
      {:ok, user} = Journal.Repo.insert(User.changeset(%User{}, user_attrs))

      %{user: user}
    end

    test "can insert a patient via Repo", %{user: user} do
      attrs = %{
        user_id: user.id,
        professional_id: 1
      }

      changeset = Patient.changeset(%Patient{}, attrs)
      assert changeset.valid?

      {:ok, patient} = Journal.Repo.insert(changeset)

      assert patient.id
      assert patient.user_id == user.id
      assert patient.professional_id == 1
      assert patient.inserted_at
      assert patient.updated_at
    end

    test "can update a patient via Repo", %{user: user} do
      # First create a patient
      attrs = %{
        user_id: user.id,
        professional_id: 1
      }

      {:ok, patient} = Journal.Repo.insert(Patient.changeset(%Patient{}, attrs))

      # Update the patient
      update_attrs = %{professional_id: 2}
      changeset = Patient.changeset(patient, update_attrs)

      {:ok, updated_patient} = Journal.Repo.update(changeset)

      assert updated_patient.professional_id == 2
      assert updated_patient.user_id == user.id
    end

    test "enforces unique composite constraint on (user_id, professional_id)", %{user: user} do
      attrs1 = %{
        user_id: user.id,
        professional_id: 1
      }

      {:ok, _patient1} = Journal.Repo.insert(Patient.changeset(%Patient{}, attrs1))

      # Try to create another patient with same user_id and professional_id
      attrs2 = %{
        user_id: user.id,
        professional_id: 1
      }

      changeset = Patient.changeset(%Patient{}, attrs2)
      assert changeset.valid?

      assert {:error, changeset} = Journal.Repo.insert(changeset)
      assert %{user_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same user_id with different professional_id", %{user: user} do
      attrs1 = %{
        user_id: user.id,
        professional_id: 1
      }

      {:ok, _patient1} = Journal.Repo.insert(Patient.changeset(%Patient{}, attrs1))

      # Create another patient with same user_id but different professional_id
      attrs2 = %{
        user_id: user.id,
        professional_id: 2
      }

      changeset = Patient.changeset(%Patient{}, attrs2)
      assert changeset.valid?

      {:ok, patient2} = Journal.Repo.insert(changeset)
      assert patient2.professional_id == 2
    end

    test "allows same professional_id with different user_id", %{user: user} do
      # Create another user with unique identifiers
      user2_attrs = unique_user_attrs(%{name: "Test User 2"})
      {:ok, user2} = Journal.Repo.insert(User.changeset(%User{}, user2_attrs))

      attrs1 = %{
        user_id: user.id,
        professional_id: 1
      }

      {:ok, _patient1} = Journal.Repo.insert(Patient.changeset(%Patient{}, attrs1))

      # Create another patient with same professional_id but different user_id
      attrs2 = %{
        user_id: user2.id,
        professional_id: 1
      }

      changeset = Patient.changeset(%Patient{}, attrs2)
      assert changeset.valid?

      {:ok, patient2} = Journal.Repo.insert(changeset)
      assert patient2.user_id == user2.id
      assert patient2.professional_id == 1
    end
  end
end
