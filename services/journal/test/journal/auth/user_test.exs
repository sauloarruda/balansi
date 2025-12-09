defmodule Journal.Auth.UserTest do
  use ExUnit.Case, async: true
  use Journal.DataCase

  alias Journal.Auth.User

  # Helper function to create unique user attributes for testing
  defp unique_user_attrs(overrides \\ %{}) do
    unique_id = System.unique_integer([:positive])
    Map.merge(%{
      name: "Test User",
      email: "test-#{unique_id}@example.com",
      cognito_id: "cognito-#{unique_id}"
    }, overrides)
  end

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        cognito_id: "cognito-123"
      }

      changeset = User.changeset(%User{}, attrs)

      assert changeset.valid?
      assert changeset.changes.name == "John Doe"
      assert changeset.changes.email == "john@example.com"
      assert changeset.changes.cognito_id == "cognito-123"
    end

    test "invalid when required fields are missing" do
      attrs = %{}

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert %{name: ["can't be blank"], email: ["can't be blank"], cognito_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when name is empty" do
      attrs = %{
        name: "",
        email: "john@example.com",
        cognito_id: "cognito-123"
      }

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when name exceeds 255 characters" do
      long_name = String.duplicate("a", 256)

      attrs = %{
        name: long_name,
        email: "john@example.com",
        cognito_id: "cognito-123"
      }

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert %{name: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "valid when name is exactly 255 characters" do
      name = String.duplicate("a", 255)

      attrs = %{
        name: name,
        email: "john@example.com",
        cognito_id: "cognito-123"
      }

      changeset = User.changeset(%User{}, attrs)

      assert changeset.valid?
    end

    test "invalid when email is empty" do
      attrs = %{
        name: "John Doe",
        email: "",
        cognito_id: "cognito-123"
      }

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when email exceeds 255 characters" do
      long_email = String.duplicate("a", 250) <> "@example.com"

      attrs = %{
        name: "John Doe",
        email: long_email,
        cognito_id: "cognito-123"
      }

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert %{email: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "invalid when email format is invalid" do
      attrs = %{
        name: "John Doe",
        email: "invalid-email",
        cognito_id: "cognito-123"
      }

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert %{email: ["must be a valid email address"]} = errors_on(changeset)
    end

    test "valid when email format is correct" do
      attrs = %{
        name: "John Doe",
        email: "john.doe@example.com",
        cognito_id: "cognito-123"
      }

      changeset = User.changeset(%User{}, attrs)

      assert changeset.valid?
    end

    test "invalid when cognito_id is empty" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        cognito_id: ""
      }

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert %{cognito_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when cognito_id exceeds 255 characters" do
      long_cognito_id = String.duplicate("a", 256)

      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        cognito_id: long_cognito_id
      }

      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert %{cognito_id: ["should be at most 255 character(s)"]} = errors_on(changeset)
    end

    test "valid when cognito_id is exactly 255 characters" do
      cognito_id = String.duplicate("a", 255)

      attrs = %{
        name: "John Doe",
        email: "john@example.com",
        cognito_id: cognito_id
      }

      changeset = User.changeset(%User{}, attrs)

      assert changeset.valid?
    end
  end

  describe "database operations" do
    test "can insert a user via Repo" do
      attrs = unique_user_attrs(%{name: "Jane Doe"})

      changeset = User.changeset(%User{}, attrs)
      assert changeset.valid?

      {:ok, user} = Journal.Repo.insert(changeset)

      assert user.id
      assert user.name == "Jane Doe"
      assert user.email == attrs.email
      assert user.cognito_id == attrs.cognito_id
      assert user.inserted_at
      assert user.updated_at
    end

    test "can update a user via Repo" do
      # First create a user
      attrs = unique_user_attrs(%{name: "Jane Doe"})
      {:ok, user} = Journal.Repo.insert(User.changeset(%User{}, attrs))

      # Update the user
      update_attrs = %{name: "Jane Smith"}
      changeset = User.changeset(user, update_attrs)

      {:ok, updated_user} = Journal.Repo.update(changeset)

      assert updated_user.name == "Jane Smith"
      assert updated_user.email == attrs.email
    end

    test "enforces unique email constraint" do
      unique_id = System.unique_integer([:positive])
      attrs1 = unique_user_attrs(%{
        name: "User One",
        email: "duplicate-#{unique_id}@example.com",
        cognito_id: "cognito-email-test-#{unique_id}"
      })

      {:ok, _user1} = Journal.Repo.insert(User.changeset(%User{}, attrs1))

      attrs2 = unique_user_attrs(%{
        name: "User Two",
        email: "duplicate-#{unique_id}@example.com",
        cognito_id: "cognito-email-test-2-#{unique_id}"
      })

      changeset = User.changeset(%User{}, attrs2)
      assert changeset.valid?

      assert {:error, changeset} = Journal.Repo.insert(changeset)
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "enforces unique cognito_id constraint" do
      unique_id = System.unique_integer([:positive])
      attrs1 = unique_user_attrs(%{
        name: "User One",
        email: "user1-#{unique_id}@example.com",
        cognito_id: "cognito-duplicate-#{unique_id}"
      })

      {:ok, _user1} = Journal.Repo.insert(User.changeset(%User{}, attrs1))

      attrs2 = unique_user_attrs(%{
        name: "User Two",
        email: "user2-#{unique_id}@example.com",
        cognito_id: "cognito-duplicate-#{unique_id}"
      })

      changeset = User.changeset(%User{}, attrs2)
      assert changeset.valid?

      assert {:error, changeset} = Journal.Repo.insert(changeset)
      assert %{cognito_id: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
