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

ActiveRecord::Schema[8.1].define(version: 2026_02_25_142345) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "exercise_status_enum", ["pending_llm", "pending_patient", "confirmed"]
  create_enum "meal_status_enum", ["pending_llm", "pending_patient", "confirmed"]
  create_enum "meal_type_enum", ["breakfast", "lunch", "snack", "dinner"]

  create_table "exercises", force: :cascade do |t|
    t.integer "calories"
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.integer "duration"
    t.bigint "journal_id", null: false
    t.integer "neat"
    t.enum "status", default: "pending_llm", null: false, enum_type: "exercise_status_enum"
    t.string "structured_description"
    t.datetime "updated_at", null: false
    t.index ["journal_id", "status"], name: "exercises_journal_status_idx"
    t.index ["journal_id"], name: "index_exercises_on_journal_id"
  end

  create_table "journals", force: :cascade do |t|
    t.integer "calories_burned"
    t.integer "calories_consumed"
    t.datetime "closed_at", precision: nil
    t.datetime "created_at", null: false
    t.text "daily_note"
    t.date "date", null: false
    t.text "feedback_improvement"
    t.text "feedback_positive"
    t.integer "feeling_today"
    t.integer "hydration_quality"
    t.bigint "patient_id", null: false
    t.integer "score"
    t.integer "sleep_quality"
    t.integer "steps_count"
    t.datetime "updated_at", null: false
    t.index ["closed_at"], name: "index_journals_on_closed_at"
    t.index ["date"], name: "index_journals_on_date"
    t.index ["patient_id", "date"], name: "journals_patient_date_unique_idx", unique: true
    t.index ["patient_id"], name: "index_journals_on_patient_id"
  end

  create_table "meals", force: :cascade do |t|
    t.text "ai_comment"
    t.integer "calories"
    t.integer "carbs"
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.integer "fats"
    t.integer "feeling"
    t.integer "gram_weight"
    t.bigint "journal_id", null: false
    t.enum "meal_type", null: false, enum_type: "meal_type_enum"
    t.integer "proteins"
    t.enum "status", default: "pending_llm", null: false, enum_type: "meal_status_enum"
    t.datetime "updated_at", null: false
    t.index ["journal_id", "status"], name: "meals_journal_status_idx"
    t.index ["journal_id"], name: "index_meals_on_journal_id"
  end

  create_table "patient_professional_accesses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "granted_by_patient_user_id", null: false
    t.bigint "patient_id", null: false
    t.bigint "professional_id", null: false
    t.datetime "updated_at", null: false
    t.index ["granted_by_patient_user_id"], name: "idx_on_granted_by_patient_user_id_c69b06733a"
    t.index ["patient_id", "professional_id"], name: "patient_prof_access_unique_idx", unique: true
    t.index ["patient_id"], name: "index_patient_professional_accesses_on_patient_id"
    t.index ["professional_id", "patient_id"], name: "patient_prof_access_prof_patient_idx"
    t.index ["professional_id"], name: "index_patient_professional_accesses_on_professional_id"
  end

  create_table "patients", force: :cascade do |t|
    t.date "birth_date"
    t.integer "bmr"
    t.datetime "clinical_assessment_last_updated_at"
    t.datetime "created_at", null: false
    t.integer "daily_calorie_goal"
    t.string "gender"
    t.decimal "height_cm", precision: 5, scale: 2
    t.integer "hydration_goal"
    t.string "phone_e164", limit: 20
    t.bigint "professional_id", null: false
    t.datetime "profile_completed_at"
    t.datetime "profile_last_updated_at"
    t.integer "steps_goal"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.decimal "weight_kg", precision: 5, scale: 2
    t.index ["professional_id"], name: "index_patients_on_professional_id"
    t.index ["user_id"], name: "index_patients_on_user_id", unique: true
  end

  create_table "professionals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_professionals_on_user_id", unique: true
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

  add_foreign_key "exercises", "journals", on_delete: :cascade
  add_foreign_key "journals", "patients", on_delete: :cascade
  add_foreign_key "meals", "journals", on_delete: :cascade
  add_foreign_key "patient_professional_accesses", "patients", on_delete: :cascade
  add_foreign_key "patient_professional_accesses", "professionals", on_delete: :cascade
  add_foreign_key "patient_professional_accesses", "users", column: "granted_by_patient_user_id"
  add_foreign_key "patients", "professionals"
  add_foreign_key "patients", "users", on_delete: :cascade
  add_foreign_key "professionals", "users", on_delete: :cascade
end
