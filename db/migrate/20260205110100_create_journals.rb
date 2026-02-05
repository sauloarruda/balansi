class CreateJournals < ActiveRecord::Migration[8.1]
  def change
    create_table :journals do |t|
      t.references :patient, null: false, foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.timestamp :closed_at
      t.integer :calories_consumed
      t.integer :calories_burned
      t.integer :score
      t.text :feedback_positive
      t.text :feedback_improvement
      t.integer :feeling_today
      t.integer :sleep_quality
      t.integer :hydration_quality
      t.integer :steps_count
      t.text :daily_note

      t.timestamps
    end

    add_index :journals, :date
    add_index :journals, :closed_at
    add_index :journals, [ :patient_id, :date ], unique: true, name: "journals_patient_date_unique_idx"
  end
end
