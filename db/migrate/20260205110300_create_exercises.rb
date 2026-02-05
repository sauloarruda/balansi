class CreateExercises < ActiveRecord::Migration[8.1]
  def change
    create_enum :exercise_status_enum, %w[pending_llm pending_patient confirmed]

    create_table :exercises do |t|
      t.references :journal, null: false, foreign_key: { on_delete: :cascade }
      t.string :description, null: false
      t.integer :duration
      t.integer :calories
      t.integer :neat
      t.string :structured_description
      t.enum :status, enum_type: "exercise_status_enum", null: false, default: "pending_llm"

      t.timestamps
    end

    add_index :exercises, [ :journal_id, :status ], name: "exercises_journal_status_idx"
  end
end
