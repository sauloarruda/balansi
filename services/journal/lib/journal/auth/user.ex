defmodule Journal.Auth.User do
  @moduledoc """
  Schema for user records linked to AWS Cognito identities.

  Each user record represents a local database entry that corresponds to
  a Cognito user identity. The cognito_id field stores the Cognito User Sub
  (unique identifier from Cognito).

  ## Fields
  - `name`: User's full name (required, max 255 characters)
  - `email`: User's email address (required, unique, max 255 characters)
  - `cognito_id`: Cognito User Sub identifier (required, unique, max 255 characters)
  - `inserted_at`: Timestamp when record was created
  - `updated_at`: Timestamp when record was last updated
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :cognito_id, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :email, :cognito_id]
  @optional_fields []

  @doc """
  Creates a changeset for a user.

  ## Examples

      iex> changeset = User.changeset(%User{}, %{name: "John Doe", email: "john@example.com", cognito_id: "cognito-123"})
      iex> changeset.valid?
      true

      iex> changeset = User.changeset(%User{}, %{})
      iex> changeset.valid?
      false
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:email, min: 1, max: 255)
    |> validate_length(:cognito_id, min: 1, max: 255)
    # Basic email validation is sufficient here since Cognito already validates email format
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    |> unique_constraint(:email, name: :users_email_key)
    |> unique_constraint(:cognito_id, name: :users_cognito_id_key)
  end
end
