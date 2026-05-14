class RemoveNeatFromExercises < ActiveRecord::Migration[8.1]
  def change
    remove_column :exercises, :neat, :integer
  end
end
