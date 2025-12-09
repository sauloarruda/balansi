defmodule Journal.Repo.Migrations.CreateUsersTable do
  use Ecto.Migration

  def up do
    create table(:users) do
      add :name, :string, size: 255, null: false
      add :email, :string, size: 255, null: false
      add :cognito_id, :string, size: 255, null: false

      timestamps(type: :utc_datetime)
    end

    # Create unique indexes
    create unique_index(:users, [:email], name: :users_email_key)
    create unique_index(:users, [:cognito_id], name: :users_cognito_id_key)
  end

  def down do
    drop table(:users)
  end
end
