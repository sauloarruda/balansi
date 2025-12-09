defmodule Journal.Repo.Migrations.AddForeignKeyToPatientsUserId do
  @moduledoc """
  Adds foreign key constraint to patients.user_id.

  This migration adds a foreign key constraint linking patients.user_id
  to users.id with CASCADE delete, ensuring referential integrity.

  When a user is deleted, all their patient records are also deleted.
  """
  use Ecto.Migration

  def up do
    # Add foreign key constraint with CASCADE delete
    # When a user is deleted, all their patient records are also deleted
    execute """
    ALTER TABLE patients
    ADD CONSTRAINT patients_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES users(id)
    ON DELETE CASCADE
    """
  end

  def down do
    # Remove foreign key constraint
    execute """
    ALTER TABLE patients
    DROP CONSTRAINT IF EXISTS patients_user_id_fkey
    """
  end
end
