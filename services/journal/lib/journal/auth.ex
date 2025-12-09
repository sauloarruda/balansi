defmodule Journal.Auth do
  @moduledoc """
  Context module for authentication and user management.

  Provides functions to:
  - Create or find users by Cognito ID
  - Create patient records linking users to professionals
  - Get professional IDs (temporary function)

  All database operations use Ecto Repo for persistence.
  """

  alias Journal.Auth.User
  alias Journal.Auth.Patient
  alias Journal.Repo

  @doc """
  Creates a user or finds an existing user by cognito_id.

  This function implements an "upsert" pattern: if a user with the given
  cognito_id already exists, it returns that user. Otherwise, it creates
  a new user with the provided attributes.

  ## Parameters
    - `cognito_id`: The Cognito User Sub identifier (required, unique)
    - `attrs`: Map of user attributes containing:
      - `name`: User's full name (required)
      - `email`: User's email address (required, unique)

  ## Returns
    - `{:ok, user}` where user is the created or found User struct
      - If user exists, returns existing user without updating attributes
    - `{:error, changeset}` on validation failure (e.g., invalid email, missing fields, duplicate email)

  ## Examples

      iex> Journal.Auth.create_or_find_user("cognito-123", %{name: "John Doe", email: "john@example.com"})
      {:ok, %Journal.Auth.User{}}

      iex> # If user already exists with same cognito_id
      iex> Journal.Auth.create_or_find_user("cognito-123", %{name: "Jane Doe", email: "jane@example.com"})
      {:ok, %Journal.Auth.User{cognito_id: "cognito-123"}}  # Returns existing user

      iex> # Error case: missing email
      iex> Journal.Auth.create_or_find_user("cognito-123", %{name: "John Doe"})
      {:error, %Ecto.Changeset{}}
  """
  def create_or_find_user(cognito_id, attrs) do
    # First, try to find existing user by cognito_id
    case Repo.get_by(User, cognito_id: cognito_id) do
      nil ->
        # User doesn't exist, create new one
        attrs_with_cognito_id = Map.put(attrs, :cognito_id, cognito_id)
        changeset = User.changeset(%User{}, attrs_with_cognito_id)

        case Repo.insert(changeset) do
          {:ok, user} -> {:ok, user}
          {:error, changeset} -> {:error, changeset}
        end

      user ->
        # User exists, return it without updating
        # Note: This intentionally does not update existing user attributes
        {:ok, user}
    end
  end

  @doc """
  Creates a patient record linking a user to a professional.

  ## Parameters
    - `user_id`: The ID of the user (required)
    - `professional_id`: The ID of the professional (required)

  ## Returns
    - `{:ok, patient}` where patient is the created Patient struct
    - `{:error, changeset}` on validation failure (e.g., duplicate patient)

  ## Examples

      iex> Journal.Auth.create_patient(1, 1)
      {:ok, %Journal.Auth.Patient{}}

      iex> # If patient already exists for this user-professional pair
      iex> Journal.Auth.create_patient(1, 1)
      {:error, %Ecto.Changeset{}}
  """
  def create_patient(user_id, professional_id) do
    attrs = %{
      user_id: user_id,
      professional_id: professional_id
    }

    changeset = Patient.changeset(%Patient{}, attrs)

    case Repo.insert(changeset) do
      {:ok, patient} -> {:ok, patient}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Gets the first professional ID (temporary function).

  This is a temporary function that returns a hardcoded professional ID.
  In the future, this will be replaced with a proper professional lookup
  when the professionals table is implemented (planned for a future phase).

  ## Returns
    - Integer representing the professional ID

  ## Examples

      iex> Journal.Auth.get_first_professional_id()
      1
  """
  def get_first_professional_id do
    # Temporary: return hardcoded professional ID
    # This will be replaced when professionals table is implemented
    1
  end
end

