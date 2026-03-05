class CreateMeals < ActiveRecord::Migration[8.1]
  def change
    create_table :meals do |t|
      t.references :journal, null: false, foreign_key: { on_delete: :cascade }
      t.string :meal_type, null: false
      t.string :description, null: false
      t.integer :proteins
      t.integer :carbs
      t.integer :fats
      t.integer :calories
      t.integer :gram_weight
      t.text :ai_comment
      t.integer :feeling
      t.string :status, null: false, default: "pending_llm"

      t.timestamps
    end

    add_index :meals, [ :journal_id, :status ], name: "meals_journal_status_idx"
  end
end
