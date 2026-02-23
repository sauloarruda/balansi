class EvolvePatientsForProfessionalArea < ActiveRecord::Migration[8.1]
  def up
    add_column :patients, :gender, :string
    add_column :patients, :birth_date, :date
    add_column :patients, :weight_kg, :decimal, precision: 5, scale: 2
    add_column :patients, :height_cm, :decimal, precision: 5, scale: 2
    add_column :patients, :phone_e164, :string, limit: 20
    add_column :patients, :profile_completed_at, :datetime
    add_column :patients, :profile_last_updated_at, :datetime

    change_column :patients, :professional_id, :bigint, using: "professional_id::bigint"

    remove_index :patients, name: "patients_user_professional_unique_idx" if index_exists?(:patients, [ :user_id, :professional_id ], name: "patients_user_professional_unique_idx")

    ensure_default_professional
    normalize_existing_patients

    remove_index :patients, :user_id if index_exists?(:patients, :user_id)
    add_index :patients, :user_id, unique: true
    add_foreign_key :patients, :professionals, column: :professional_id
  end

  def down
    remove_foreign_key :patients, column: :professional_id if foreign_key_exists?(:patients, :professionals, column: :professional_id)

    remove_index :patients, :user_id if index_exists?(:patients, :user_id)
    add_index :patients, [ :user_id, :professional_id ], unique: true, name: "patients_user_professional_unique_idx"
    add_index :patients, :user_id unless index_exists?(:patients, :user_id)

    change_column :patients, :professional_id, :integer, using: "professional_id::integer"

    remove_column :patients, :profile_last_updated_at
    remove_column :patients, :profile_completed_at
    remove_column :patients, :phone_e164
    remove_column :patients, :height_cm
    remove_column :patients, :weight_kg
    remove_column :patients, :birth_date
    remove_column :patients, :gender
  end

  private

  def ensure_default_professional
    return unless select_value("SELECT 1 FROM patients LIMIT 1")

    existing_user_id = select_value("SELECT id FROM users ORDER BY id ASC LIMIT 1")
    return if existing_user_id.blank?

    now_sql = connection.quote(Time.current)

    execute <<~SQL
      INSERT INTO professionals (id, user_id, created_at, updated_at)
      VALUES (1, #{existing_user_id.to_i}, #{now_sql}, #{now_sql})
      ON CONFLICT (id) DO NOTHING;
    SQL

    execute <<~SQL
      SELECT setval(
        pg_get_serial_sequence('professionals', 'id'),
        COALESCE((SELECT MAX(id) FROM professionals), 1),
        true
      );
    SQL
  end

  def normalize_existing_patients
    execute <<~SQL
      UPDATE patients
      SET professional_id = 1
      WHERE professional_id IS DISTINCT FROM 1;
    SQL

    execute <<~SQL
      DELETE FROM patients AS p
      USING (
        SELECT id
        FROM (
          SELECT
            id,
            ROW_NUMBER() OVER (
              PARTITION BY user_id
              ORDER BY updated_at DESC NULLS LAST, id DESC
            ) AS row_num
          FROM patients
        ) ranked
        WHERE ranked.row_num > 1
      ) AS duplicates
      WHERE p.id = duplicates.id;
    SQL
  end
end
