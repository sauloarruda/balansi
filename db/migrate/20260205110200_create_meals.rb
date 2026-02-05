class CreateMeals < ActiveRecord::Migration[8.1]
  def change
    create_enum :meal_type_enum, %w[breakfast lunch snack dinner]
    create_enum :meal_status_enum, %w[pending_llm pending_patient confirmed]

    create_table :meals do |t|
      t.references :journal, null: false, foreign_key: { on_delete: :cascade }
      t.enum :meal_type, enum_type: "meal_type_enum", null: false
      t.string :description, null: false
      t.integer :proteins
      t.integer :carbs
      t.integer :fats
      t.integer :calories
      t.integer :gram_weight
      t.text :ai_comment
      t.integer :feeling
      t.enum :status, enum_type: "meal_status_enum", null: false, default: "pending_llm"

      t.timestamps
    end

    add_index :meals, [ :journal_id, :status ], name: "meals_journal_status_idx"
  end
end
