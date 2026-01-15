class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, limit: 255, null: false
      t.string :email, limit: 255, null: false
      t.string :cognito_id, limit: 255, null: false
      t.string :timezone, limit: 50, null: false, default: "America/Sao_Paulo"
      t.string :language, limit: 10, null: false, default: "pt"

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :cognito_id, unique: true
  end
end
