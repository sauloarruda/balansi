class CreateMealRecipeReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :meal_recipe_references do |t|
      t.references :meal, null: false, foreign_key: { on_delete: :cascade }
      t.references :recipe, foreign_key: { on_delete: :nullify }
      t.string :recipe_name, null: false
      t.decimal :portion_size_grams, precision: 8, scale: 2, null: false
      t.integer :calories_per_portion
      t.decimal :proteins_per_portion, precision: 8, scale: 2
      t.decimal :carbs_per_portion, precision: 8, scale: 2
      t.decimal :fats_per_portion, precision: 8, scale: 2

      t.timestamps
    end

    add_index :meal_recipe_references, [ :meal_id, :recipe_id ], name: "meal_recipe_refs_meal_recipe_idx"
  end
end
