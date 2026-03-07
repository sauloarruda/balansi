class CreateRodauth < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_hash, :string

    create_table :user_remember_keys, id: false do |t|
      t.integer :id, primary_key: true
      t.foreign_key :users, column: :id
      t.string :key, null: false
      t.datetime :deadline, null: false
    end

    add_index :user_remember_keys, :id, unique: true
  end
end
