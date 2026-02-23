class CreatePatientProfessionalAccesses < ActiveRecord::Migration[8.1]
  def change
    create_table :patient_professional_accesses do |t|
      t.references :patient, null: false, foreign_key: { on_delete: :cascade }
      t.references :professional, null: false, foreign_key: { on_delete: :cascade }
      t.references :granted_by_patient_user, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :patient_professional_accesses,
      [ :patient_id, :professional_id ],
      unique: true,
      name: "patient_prof_access_unique_idx"
    add_index :patient_professional_accesses,
      [ :professional_id, :patient_id ],
      name: "patient_prof_access_prof_patient_idx"
  end
end
