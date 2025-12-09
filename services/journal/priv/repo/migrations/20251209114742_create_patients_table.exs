defmodule Journal.Repo.Migrations.CreatePatientsTable do
  use Ecto.Migration

  def up do
    create table(:patients) do
      add :user_id, :integer, null: false
      add :professional_id, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    # Create indexes for lookups
    create index(:patients, [:user_id], name: :patients_user_id_idx)
    create index(:patients, [:professional_id], name: :patients_professional_id_idx)
  end

  def down do
    drop table(:patients)
  end
end
