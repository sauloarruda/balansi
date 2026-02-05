class AddJournalFieldsToPatients < ActiveRecord::Migration[8.1]
  def change
    add_column :patients, :daily_calorie_goal, :integer
    add_column :patients, :bmr, :integer
    add_column :patients, :steps_goal, :integer
    add_column :patients, :hydration_goal, :integer
  end
end
