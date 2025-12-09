defmodule Journal.Repo.Migrations.CreatePatientsTable do
  @moduledoc """
  Creates the patients table for linking users to professionals.

  This table establishes the relationship between users (patients) and
  professionals (nutritionists). One user can have multiple patient records,
  one per professional relationship.

  ## Indexes
  - Index on user_id (patients_user_id_idx) - for user lookup
  - Index on professional_id (patients_professional_id_idx) - for professional lookup
  - Unique composite index on (user_id, professional_id) - ensures one patient record per user-professional pair

  ## Foreign Keys
  - user_id references users.id with CASCADE delete
  - professional_id references a future professionals table (no FK constraint yet)
  """
  use Ecto.Migration

  def up do
    # Create patients table
    # Links users to professionals (nutritionists)
    # Created during authentication callback
    create table(:patients) do
      # Reference to users.id with CASCADE delete
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # Reference to future professionals table (no FK constraint yet)
      add :professional_id, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    # Create indexes for lookups
    # Index for finding all patients for a user
    create index(:patients, [:user_id], name: :patients_user_id_idx)
    # Index for finding all patients for a professional
    create index(:patients, [:professional_id], name: :patients_professional_id_idx)
    # Composite unique index ensures one patient record per user-professional pair
    # Also optimizes the common query: find patient by user_id AND professional_id
    create unique_index(:patients, [:user_id, :professional_id],
      name: :patients_user_professional_unique_idx
    )
  end

  def down do
    drop table(:patients)
  end
end
