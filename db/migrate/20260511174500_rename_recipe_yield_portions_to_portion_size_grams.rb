class RenameRecipeYieldPortionsToPortionSizeGrams < ActiveRecord::Migration[8.1]
  def up
    rename_column :recipes, :yield_portions, :portion_size_grams
    change_column :recipes, :portion_size_grams, :decimal, precision: 8, scale: 2, null: false
  end

  def down
    change_column :recipes, :portion_size_grams, :integer, null: false
    rename_column :recipes, :portion_size_grams, :yield_portions
  end
end
