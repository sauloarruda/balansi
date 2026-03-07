class AddVerifyAccountToUsers < ActiveRecord::Migration[8.1]
  def change
    # Rodauth lifecycle status: 1=unverified, 2=open/verified, 3=closed.
    # Default is 2 so all existing users remain active after migration.
    add_column :users, :status_id, :integer, null: false, default: 2

    create_table :account_verification_keys, id: false do |t|
      t.integer  :id, null: false, primary_key: true
      t.string   :key, null: false
      t.datetime :requested_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :email_last_sent, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_foreign_key :account_verification_keys, :users, column: :id
  end
end
