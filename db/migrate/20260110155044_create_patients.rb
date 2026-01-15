class CreatePatients < ActiveRecord::Migration[8.1]
  def change
    create_table :patients do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :professional_id, null: false

      t.timestamps
    end

    # Note: user_id index is automatically created by t.references above
    add_index :patients, :professional_id
    add_index :patients, [ :user_id, :professional_id ], unique: true, name: "patients_user_professional_unique_idx"
  end
end
