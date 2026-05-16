class AddDiscardedAtToRecipes < ActiveRecord::Migration[8.1]
  def change
    add_column :recipes, :discarded_at, :datetime
    add_index :recipes, :discarded_at
  end
end
