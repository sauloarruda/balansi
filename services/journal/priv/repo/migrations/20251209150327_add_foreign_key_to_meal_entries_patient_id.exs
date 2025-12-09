defmodule Journal.Repo.Migrations.AddForeignKeyToMealEntriesPatientId do
  @moduledoc """
  Adds foreign key constraint to meal_entries.patient_id.

  This migration adds a foreign key constraint linking meal_entries.patient_id
  to patients.id with CASCADE delete, ensuring referential integrity.

  Note: If there are existing meal_entries with invalid patient_id values,
  this migration will fail. Clean up orphaned records before running.
  """
  use Ecto.Migration

  def up do
    # Add foreign key constraint with CASCADE delete
    # When a patient is deleted, all their meal entries are also deleted
    execute """
    ALTER TABLE meal_entries
    ADD CONSTRAINT meal_entries_patient_id_fkey
    FOREIGN KEY (patient_id)
    REFERENCES patients(id)
    ON DELETE CASCADE
    """
  end

  def down do
    # Remove foreign key constraint
    execute """
    ALTER TABLE meal_entries
    DROP CONSTRAINT IF EXISTS meal_entries_patient_id_fkey
    """
  end
end
