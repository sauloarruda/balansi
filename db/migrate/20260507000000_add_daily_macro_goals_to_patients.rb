class AddDailyMacroGoalsToPatients < ActiveRecord::Migration[8.1]
  def change
    change_table :patients do |t|
      t.integer :daily_carbs_goal, null: false, default: 0
      t.integer :daily_proteins_goal, null: false, default: 0
      t.integer :daily_fats_goal, null: false, default: 0
    end
  end
end
