defmodule Journal.Repo.Migrations.CreateMealEntries do
  use Ecto.Migration

  def up do
    # Create enums
    execute """
    CREATE TYPE meal_type AS ENUM ('breakfast', 'lunch', 'snack', 'dinner')
    """

    execute """
    CREATE TYPE entry_status AS ENUM ('pending', 'processing', 'in_review', 'confirmed')
    """

    # Create meal_entries table
    create table(:meal_entries) do
      add :patient_id, :integer, null: false
      add :date, :date, null: false
      add :meal_type, :meal_type, null: false
      add :original_description, :text, null: false
      add :protein_g, :decimal, precision: 10, scale: 2
      add :carbs_g, :decimal, precision: 10, scale: 2
      add :fat_g, :decimal, precision: 10, scale: 2
      add :calories_kcal, :integer
      add :weight_g, :integer
      add :ai_comment, :text
      add :status, :entry_status, null: false, default: "pending"
      add :has_manual_override, :boolean, default: false
      add :overridden_fields, :jsonb, default: "{}"
      add :source_recipe_id, :integer

      timestamps(type: :utc_datetime)
    end

    # Create indexes
    create index(:meal_entries, [:patient_id, :date])
    create index(:meal_entries, [:status])
  end

  def down do
    drop table(:meal_entries)

    execute "DROP TYPE entry_status"
    execute "DROP TYPE meal_type"
  end
end
