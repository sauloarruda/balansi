class CreateExercises < ActiveRecord::Migration[8.1]
  def change
    create_table :exercises do |t|
      t.references :journal, null: false, foreign_key: { on_delete: :cascade }
      t.string :description, null: false
      t.integer :duration
      t.integer :calories
      t.integer :neat
      t.string :structured_description
      t.string :status, null: false, default: "pending_llm"

      t.timestamps
    end

    add_index :exercises, [ :journal_id, :status ], name: "exercises_journal_status_idx"
  end
end
