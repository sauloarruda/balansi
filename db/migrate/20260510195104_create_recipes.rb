class CreateRecipes < ActiveRecord::Migration[8.1]
  def change
    create_table :recipes do |t|
      t.references :patient, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :ingredients, null: false
      t.text :instructions
      t.integer :yield_portions, null: false
      t.integer :calories
      t.integer :proteins
      t.integer :carbs
      t.integer :fats

      t.timestamps
    end

    add_index :recipes, [ :patient_id, :name ], name: "recipes_patient_name_idx"
  end
end
