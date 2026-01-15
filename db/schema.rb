# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_10_155044) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "patients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "professional_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["professional_id"], name: "index_patients_on_professional_id"
    t.index ["user_id", "professional_id"], name: "patients_user_professional_unique_idx", unique: true
    t.index ["user_id"], name: "index_patients_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "cognito_id", limit: 255, null: false
    t.datetime "created_at", null: false
    t.string "email", limit: 255, null: false
    t.string "language", limit: 10, default: "pt", null: false
    t.string "name", limit: 255, null: false
    t.string "timezone", limit: 50, default: "America/Sao_Paulo", null: false
    t.datetime "updated_at", null: false
    t.index ["cognito_id"], name: "index_users_on_cognito_id", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "patients", "users", on_delete: :cascade
end
