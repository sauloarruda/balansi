defmodule Journal.Repo.Migrations.CreateUsersTable do
  @moduledoc """
  Creates the users table for authentication.

  This table stores local user records linked to AWS Cognito identities.
  The cognito_id field stores the Cognito User Sub (unique identifier).

  ## Indexes
  - Unique index on email (users_email_key)
  - Unique index on cognito_id (users_cognito_id_key)
  """
  use Ecto.Migration

  def up do
    # Create users table
    # Links local user records to AWS Cognito identities via cognito_id
    create table(:users) do
      add :name, :string, size: 255, null: false
      add :email, :string, size: 255, null: false
      # Cognito User Sub (unique identifier from Cognito)
      # Max length: 128 characters (UUID format)
      add :cognito_id, :string, size: 255, null: false

      timestamps(type: :utc_datetime)
    end

    # Create unique indexes
    # Email must be unique for login purposes
    create unique_index(:users, [:email], name: :users_email_key)
    # Cognito ID must be unique to ensure one-to-one mapping with Cognito identities
    create unique_index(:users, [:cognito_id], name: :users_cognito_id_key)
  end

  def down do
    drop table(:users)
  end
end
