defmodule Journal.AuthTest do
  @moduledoc """
  Tests for Journal.Auth context module.

  Tests cover:
  - Creating or finding users by Cognito ID
  - Creating patient records
  - Getting professional IDs
  - Error handling for validation failures
  - Duplicate user/patient creation scenarios
  """
  use ExUnit.Case, async: true
  use Journal.DataCase

  alias Journal.Auth
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

  describe "create_or_find_user/2" do
    test "creates a new user when cognito_id doesn't exist" do
      cognito_id = "cognito-new-user-#{System.unique_integer([:positive])}"
      attrs = %{
        name: "John Doe",
        email: "john-#{System.unique_integer([:positive])}@example.com"
      }

      assert {:ok, user} = Auth.create_or_find_user(cognito_id, attrs)

      assert user.id
      assert user.name == attrs.name
      assert user.email == attrs.email
      assert user.cognito_id == cognito_id
      assert user.inserted_at
      assert user.updated_at
    end

    test "finds existing user when cognito_id already exists" do
      # Create a user first
      cognito_id = "cognito-existing-#{System.unique_integer([:positive])}"
      attrs1 = %{
        name: "Jane Doe",
        email: "jane-#{System.unique_integer([:positive])}@example.com"
      }

      assert {:ok, existing_user} = Auth.create_or_find_user(cognito_id, attrs1)

      # Try to create/find again with different attributes
      attrs2 = %{
        name: "Jane Smith",
        email: "jane-smith-#{System.unique_integer([:positive])}@example.com"
      }

      assert {:ok, found_user} = Auth.create_or_find_user(cognito_id, attrs2)

      # Should return the existing user, not create a new one
      assert found_user.id == existing_user.id
      assert found_user.cognito_id == existing_user.cognito_id
      assert found_user.name == existing_user.name
      assert found_user.email == existing_user.email
    end

    test "returns error when required fields are missing" do
      cognito_id = "cognito-invalid-#{System.unique_integer([:positive])}"
      attrs = %{name: "John Doe"}  # Missing email

      assert {:error, changeset} = Auth.create_or_find_user(cognito_id, attrs)

      refute changeset.valid?
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error when email format is invalid" do
      cognito_id = "cognito-invalid-email-#{System.unique_integer([:positive])}"
      attrs = %{
        name: "John Doe",
        email: "invalid-email"
      }

      assert {:error, changeset} = Auth.create_or_find_user(cognito_id, attrs)

      refute changeset.valid?
      assert %{email: ["must be a valid email address"]} = errors_on(changeset)
    end

    test "returns error when email already exists for different cognito_id" do
      # Create first user
      cognito_id1 = "cognito-email-test-1-#{System.unique_integer([:positive])}"
      email = "duplicate-#{System.unique_integer([:positive])}@example.com"
      attrs1 = %{
        name: "User One",
        email: email
      }

      assert {:ok, _user1} = Auth.create_or_find_user(cognito_id1, attrs1)

      # Try to create user with same email but different cognito_id
      cognito_id2 = "cognito-email-test-2-#{System.unique_integer([:positive])}"
      attrs2 = %{
        name: "User Two",
        email: email
      }

      assert {:error, changeset} = Auth.create_or_find_user(cognito_id2, attrs2)

      refute changeset.valid?
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "handles duplicate creation attempts gracefully" do
      # This test simulates a race condition scenario
      cognito_id = "cognito-race-#{System.unique_integer([:positive])}"
      attrs = %{
        name: "Race User",
        email: "race-#{System.unique_integer([:positive])}@example.com"
      }

      # First creation succeeds
      assert {:ok, user1} = Auth.create_or_find_user(cognito_id, attrs)

      # Second call with same cognito_id should return existing user
      assert {:ok, user2} = Auth.create_or_find_user(cognito_id, attrs)

      assert user1.id == user2.id
      assert user1.cognito_id == user2.cognito_id
    end
  end

  describe "create_patient/2" do
    setup do
      # Create a user for testing
      user_attrs = unique_user_attrs()
      {:ok, user} = Journal.Repo.insert(User.changeset(%User{}, user_attrs))

      %{user: user}
    end

    test "creates a patient record successfully", %{user: user} do
      professional_id = 1

      assert {:ok, patient} = Auth.create_patient(user.id, professional_id)

      assert patient.id
      assert patient.user_id == user.id
      assert patient.professional_id == professional_id
      assert patient.inserted_at
      assert patient.updated_at
    end

    test "returns error when user_id is invalid", %{user: _user} do
      invalid_user_id = 999_999
      professional_id = 1

      assert {:error, changeset} = Auth.create_patient(invalid_user_id, professional_id)

      # Foreign key constraint violation should be handled gracefully
      refute changeset.valid?
      assert %{user_id: ["does not exist"]} = errors_on(changeset)
    end

    test "returns error when professional_id is invalid" do
      # Create a user for testing
      user_attrs = unique_user_attrs()
      {:ok, user} = Journal.Repo.insert(User.changeset(%User{}, user_attrs))

      invalid_professional_id = 0

      assert {:error, changeset} = Auth.create_patient(user.id, invalid_professional_id)

      refute changeset.valid?
      assert %{professional_id: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "enforces unique composite constraint on (user_id, professional_id)", %{user: user} do
      professional_id = 1

      # Create first patient
      assert {:ok, _patient1} = Auth.create_patient(user.id, professional_id)

      # Try to create duplicate patient
      assert {:error, changeset} = Auth.create_patient(user.id, professional_id)

      refute changeset.valid?
      assert %{user_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same user with different professional_id", %{user: user} do
      professional_id1 = 1
      professional_id2 = 2

      # Create first patient
      assert {:ok, patient1} = Auth.create_patient(user.id, professional_id1)

      # Create second patient with different professional_id
      assert {:ok, patient2} = Auth.create_patient(user.id, professional_id2)

      assert patient1.user_id == patient2.user_id
      assert patient1.professional_id == professional_id1
      assert patient2.professional_id == professional_id2
    end

    test "allows same professional_id with different user_id", %{user: user} do
      professional_id = 1

      # Create first patient
      assert {:ok, patient1} = Auth.create_patient(user.id, professional_id)

      # Create another user
      user2_attrs = unique_user_attrs()
      {:ok, user2} = Journal.Repo.insert(User.changeset(%User{}, user2_attrs))

      # Create second patient with different user_id but same professional_id
      assert {:ok, patient2} = Auth.create_patient(user2.id, professional_id)

      assert patient1.professional_id == patient2.professional_id
      assert patient1.user_id != patient2.user_id
    end
  end

  describe "get_first_professional_id/0" do
    test "returns hardcoded professional ID" do
      assert Auth.get_first_professional_id() == 1
    end

    test "always returns the same professional ID" do
      id1 = Auth.get_first_professional_id()
      id2 = Auth.get_first_professional_id()

      assert id1 == id2
      assert id1 == 1
    end
  end
end

