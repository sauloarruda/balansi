class AddInviteCodeToProfessionals < ActiveRecord::Migration[8.1]
  def up
    add_column :professionals, :invite_code, :string, limit: 6
    backfill_invite_codes
    change_column_null :professionals, :invite_code, false
    add_index :professionals, :invite_code, unique: true
  end

  def down
    remove_index :professionals, :invite_code if index_exists?(:professionals, :invite_code)
    remove_column :professionals, :invite_code
  end

  private

  def backfill_invite_codes
    Professional.find_each do |professional|
      loop do
        code = SecureRandom.alphanumeric(6).upcase
        unless Professional.exists?(invite_code: code)
          professional.update_columns(invite_code: code)
          break
        end
      end
    end
  end
end
