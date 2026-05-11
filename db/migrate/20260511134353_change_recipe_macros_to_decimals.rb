class ChangeRecipeMacrosToDecimals < ActiveRecord::Migration[8.1]
  def up
    change_column :recipes, :proteins, :decimal, precision: 8, scale: 2
    change_column :recipes, :carbs, :decimal, precision: 8, scale: 2
    change_column :recipes, :fats, :decimal, precision: 8, scale: 2
  end

  def down
    change_column :recipes, :proteins, :integer
    change_column :recipes, :carbs, :integer
    change_column :recipes, :fats, :integer
  end
end
