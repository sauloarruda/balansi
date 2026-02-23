class CreateProfessionals < ActiveRecord::Migration[8.1]
  def change
    create_table :professionals do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.timestamps
    end
  end
end
