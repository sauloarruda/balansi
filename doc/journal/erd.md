# Engineering Requirements Document — Journal Module (Balansi)

## 1. Architecture Overview

The Journal module is the core daily tracking experience of Balansi, allowing patients to log meals and exercises with AI-assisted analysis and receive daily feedback based on nutritionist-defined scoring rules.

**Key Components:**
- **Frontend**: Rails Slim views for daily journal, meal/exercise entry and review screens
- **Backend**: Ruby on Rails application (handles journal operations, LLM integration)
- **AI Service**: OpenAI (latest model - meal analysis, exercise analysis, daily scoring)
- **Database**: PostgreSQL (journals, meals, exercises tables)

**Key Design Decisions:**
- **Template Engine**: Uses Slim for all views (`.slim` files) for cleaner, more maintainable templates
- **UI Framework**: TailwindCSS 3.4+ with Flowbite for pre-built components (forms, modals, tables, date pickers)
- **Journal Ownership**: Journals belong to Patients (not Users directly) to ensure data isolation per professional
- **Auto-Creation**: Journal records are created automatically when the first meal or exercise is logged for a date
- **Status Workflow**: Meals and exercises have 3 states: `pending_llm` (awaiting AI response), `pending_patient` (awaiting user confirmation), and `confirmed` (user confirmed). Only `confirmed` entries are counted in daily totals
- **Daily Closure**: Users can close a day after answering daily metrics questions; closed days can be edited up to 2 days after journal date
- **Pending Cleanup**: All `pending_llm` and `pending_patient` entries are automatically deleted when a day is closed
- **Data Isolation**: All journal data is isolated per professional via `patient.professional_id` (immutable)
- **LLM Integration**: Synchronous LLM calls with retry mechanism and rate limiting
- **No Caching**: LLM response caching is deferred to future versions (v1 scope)
- **Timezone Handling**: Uses `users.timezone` for date calculations (via ApplicationController)
- **Language Handling**: Uses `users.language` for LLM prompts and responses

---

## 2. Data Model / ERD

### 2.1 Entities

#### Patient (Extended)

The `patients` table is extended with additional fields for journal functionality.

**New Fields Added:**

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `bmr` | INTEGER | NULL | Basal Metabolic Rate (kcal/day) |
| `daily_calorie_goal` | INTEGER | NULL | Daily calorie goal set by nutritionist (kcal) |
| `steps_goal` | INTEGER | NULL | Daily steps goal |
| `hydration_goal` | INTEGER | NULL | Daily hydration goal (ml) |

**Notes:**
- These fields are nullable to allow gradual population as patient profiles are completed
- `daily_calorie_goal` is used for progress bar calculations and daily scoring
- `bmr` is used to calculate total calories burned (BMR + exercises)
- `steps_goal` and `hydration_goal` are used for daily metrics evaluation
- `professional_id` is **immutable** once set (enforced at model level) to ensure data isolation

#### Journal

The `journals` table represents a daily journal entry for a patient. Created automatically when the first meal or exercise is logged for a date.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | SERIAL | PRIMARY KEY | Auto-incrementing journal ID |
| `patient_id` | INTEGER | NOT NULL | Foreign key to patients.id (CASCADE delete) |
| `date` | DATE | NOT NULL | Journal date (timezone-aware via user.timezone) |
| `closed_at` | TIMESTAMP(0) | NULL | Timestamp when day was closed (NULL if not closed) |
| `calories_consumed` | INTEGER | NULL | Total calories from confirmed meals (calculated on closure) |
| `calories_burned` | INTEGER | NULL | Total calories burned (BMR + confirmed exercises, calculated on closure) |
| `score` | INTEGER | NULL | Daily score (1-5, calculated by LLM on closure) |
| `feedback_positive` | TEXT | NULL | "What went well" feedback from LLM (in user's language) |
| `feedback_improvement` | TEXT | NULL | "What to improve" feedback from LLM (in user's language) |
| `feeling_today` | INTEGER | NULL | How patient felt about the plan (1=bad, 2=ok, 3=good, answered before closure) |
| `sleep_quality` | INTEGER | NULL | Sleep quality last night (1=poor, 2=good, 3=excellent, answered before closure) |
| `hydration_quality` | INTEGER | NULL | Hydration during the day (1=poor, 2=good, 3=excellent, compared to goal) |
| `steps_count` | INTEGER | NULL | Daily steps count (answered before closure) |
| `daily_note` | TEXT | NULL | Free text note from patient (optional) |
| `created_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation timestamp |
| `updated_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record last update timestamp |

**Indexes:**
- Primary Key: `journals_pkey` on `id`
- Index: `journals_patient_id_idx` on `patient_id` (for patient lookup)
- Unique Index: `journals_patient_date_unique_idx` on `(patient_id, date)` (ensures one journal per patient per date, also optimizes date range queries per patient)
- Index: `journals_closed_at_idx` on `closed_at` (for filtering closed/open days)

**Foreign Keys:**
- `patient_id` references `patients.id` with CASCADE delete (when patient is deleted, all journals are deleted)

**Notes:**
- Journal is created automatically when first meal or exercise is logged for a date
- `date` is stored as DATE type (no time component) - timezone handling is done at application level using `user.timezone`
- `closed_at` is NULL until day is closed; once closed, daily totals and score are calculated
- `calories_consumed` and `calories_burned` are calculated from confirmed meals/exercises only
- Daily metrics (`feeling_today`, `sleep_quality`, `hydration_quality`, `steps_count`, `daily_note`) are collected before closure
- **Scale values**: `feeling_today`, `sleep_quality`, and `hydration_quality` use integer scale (1-3) where 1 is worst and 3 is best. This allows future expansion to 1-5 scale if needed.
- Closed days can be edited up to 2 days after `date`; after that, they become read-only
- `score`, `feedback_positive`, and `feedback_improvement` are generated by LLM during closure

#### Meal

The `meals` table stores meal entries with AI-analyzed nutrition data.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | SERIAL | PRIMARY KEY | Auto-incrementing meal ID |
| `journal_id` | INTEGER | NOT NULL | Foreign key to journals.id (CASCADE delete) |
| `meal_type` | VARCHAR(20) | NOT NULL | Meal type: breakfast, lunch, snack, dinner |
| `description` | VARCHAR(140) | NOT NULL | Free text description of the meal |
| `proteins` | INTEGER | NULL | Proteins in grams (from LLM or manual entry) |
| `carbs` | INTEGER | NULL | Carbohydrates in grams (from LLM or manual entry) |
| `fats` | INTEGER | NULL | Fats in grams (from LLM or manual entry) |
| `calories` | INTEGER | NULL | Calories in kcal (from LLM or manual entry) |
| `gram_weight` | INTEGER | NULL | Estimated total gram weight in grams (from LLM or manual entry) |
| `ai_comment` | TEXT | NULL | AI-generated comment about the meal (in user's language) |
| `feeling` | INTEGER | NULL | Feeling indicator: 1 = positive, 0 = negative |
| `status` | VARCHAR(20) | NOT NULL, DEFAULT 'pending_llm' | Status: pending_llm, pending_patient, confirmed |
| `created_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation timestamp |
| `updated_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record last update timestamp |

**Indexes:**
- Primary Key: `meals_pkey` on `id`
- Index: `meals_journal_id_idx` on `journal_id` (for journal lookup)
- Composite Index: `meals_journal_status_idx` on `(journal_id, status)` (optimizes common queries filtering by journal and status)

**Foreign Keys:**
- `journal_id` references `journals.id` with CASCADE delete (when journal is deleted, all meals are deleted)

**Notes:**
- `meal_type` is a fixed enum: `breakfast`, `lunch`, `snack`, `dinner` (not configurable in v1)
- `description` is limited to 140 characters (matches PRD requirement)
- **Status workflow**:
  - `pending_llm`: Created when user submits description, awaiting LLM response
  - `pending_patient`: LLM response received, awaiting user confirmation (shown in review screen)
  - `confirmed`: User confirmed the meal (either accepted as-is or after manual adjustments)
- Only `confirmed` meals are counted in daily totals (`calories_consumed` calculation)
- Users can edit or delete confirmed meals; editing does not change status back to pending states
- All `pending_llm` and `pending_patient` meals are deleted when journal day is closed
- `feeling` is 1 for positive/nutritionally good meals, 0 for not ideal meals

#### Exercise

The `exercises` table stores exercise entries with AI-analyzed metrics.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| `id` | SERIAL | PRIMARY KEY | Auto-incrementing exercise ID |
| `journal_id` | INTEGER | NOT NULL | Foreign key to journals.id (CASCADE delete) |
| `description` | VARCHAR(140) | NOT NULL | Free text description of the exercise |
| `duration` | INTEGER | NULL | Duration in minutes (from LLM or manual entry) |
| `calories` | INTEGER | NULL | Calories burned in kcal (from LLM or manual entry) |
| `neat` | INTEGER | NULL | NEAT (Non-Exercise Activity Thermogenesis) in kcal (from LLM or manual entry) |
| `structured_description` | VARCHAR(255) | NULL | Structured description from LLM (e.g., "5 km moderate run") |
| `status` | VARCHAR(20) | NOT NULL, DEFAULT 'pending_llm' | Status: pending_llm, pending_patient, confirmed |
| `created_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record creation timestamp |
| `updated_at` | TIMESTAMP(0) | NOT NULL, DEFAULT CURRENT_TIMESTAMP | Record last update timestamp |

**Indexes:**
- Primary Key: `exercises_pkey` on `id`
- Index: `exercises_journal_id_idx` on `journal_id` (for journal lookup)
- Composite Index: `exercises_journal_status_idx` on `(journal_id, status)` (optimizes common queries filtering by journal and status)

**Foreign Keys:**
- `journal_id` references `journals.id` with CASCADE delete (when journal is deleted, all exercises are deleted)

**Notes:**
- `description` is limited to 140 characters (matches PRD requirement)
- **Status workflow**:
  - `pending_llm`: Created when user submits description, awaiting LLM response
  - `pending_patient`: LLM response received, awaiting user confirmation (shown in review screen)
  - `confirmed`: User confirmed the exercise (either accepted as-is or after manual adjustments)
- Only `confirmed` exercises are counted in daily energy expenditure (`calories_burned` calculation)
- Users can edit or delete confirmed exercises; editing does not change status back to pending states
- All `pending_llm` and `pending_patient` exercises are deleted when journal day is closed
- `neat` is 0 if not applicable to the exercise type
- `structured_description` is generated by LLM for consistency and clarity

### 2.2 Entity Relationship Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                           User                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ id (PK)                                                   │  │
│  │ timezone (for date calculations)                          │  │
│  │ language (for LLM prompts/responses)                      │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ has_many
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         Patient                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ id (PK)                                                   │  │
│  │ user_id (FK → users.id)                                   │  │
│  │ professional_id (immutable, for data isolation)            │  │
│  │ daily_calorie_goal (for progress bar & scoring)           │  │
│  │ bmr (Basal Metabolic Rate)                                  │  │
│  │ steps_goal (daily steps target)                           │  │
│  │ hydration_goal (daily hydration target in ml)            │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ has_many
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                          Journal                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ id (PK)                                                   │  │
│  │ patient_id (FK → patients.id)                             │  │
│  │ date (unique per patient)                                 │  │
│  │ closed_at (NULL if not closed)                            │  │
│  │ calories_consumed (from confirmed meals)                  │  │
│  │ calories_burned (BMR + confirmed exercises)                │  │
│  │ score (1-5, from LLM)                                      │  │
│  │ feedback_positive (from LLM)                              │  │
│  │ feedback_improvement (from LLM)                           │  │
│  │ feeling_today, sleep_quality, hydration_quality          │  │
│  │ steps_count, daily_note                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         │                                    │
         │ has_many                           │ has_many
         │                                    │
         ▼                                    ▼
┌──────────────────────────┐    ┌──────────────────────────┐
│         Meal              │    │       Exercise           │
│  ┌──────────────────────┐ │    │  ┌──────────────────────┐ │
│  │ id (PK)              │ │    │  │ id (PK)              │ │
│  │ journal_id (FK)      │ │    │  │ journal_id (FK)      │ │
│  │ meal_type            │ │    │  │ description          │ │
│  │ description          │ │    │  │ duration             │ │
│  │ proteins, carbs,     │ │    │  │ calories             │ │
│  │ fats, calories       │ │    │  │ neat                 │ │
│  │ gram_weight          │ │    │  │ structured_desc      │ │
│  │ ai_comment           │ │    │  │ status               │ │
│  │ feeling              │ │    │  │ status               │ │
│  │ status               │ │    │  └──────────────────────┘ │
│  └──────────────────────┘ │    └──────────────────────────┘
└──────────────────────────┘
```

**Relationship Summary:**
- `User` has_many `Patient` (one user can have multiple patient records, one per professional)
- `Patient` belongs_to `User` and has_many `Journal`
- `Journal` belongs_to `Patient` and has_many `Meal` and has_many `Exercise`
- `Meal` belongs_to `Journal`
- `Exercise` belongs_to `Journal`

**Data Isolation:**
- All journal data is isolated per professional via `patient.professional_id`
- `patient.professional_id` is immutable once set (enforced at model level)
- Nutritionists can view the same journal view as patients (read-only access)

---

## 3. Database Schema / Migrations

### 3.1 Patients Table (Extended)

**Migration**: `YYYYMMDDHHMMSS_add_journal_fields_to_patients.rb` (new)

```ruby
class AddJournalFieldsToPatients < ActiveRecord::Migration[8.1]
  def change
    add_column :patients, :daily_calorie_goal, :integer, null: true
    add_column :patients, :bmr, :integer, null: true
    add_column :patients, :steps_goal, :integer, null: true
    add_column :patients, :hydration_goal, :integer, null: true

  end
end
```

**Field Descriptions:**
- **daily_calorie_goal**: Daily calorie goal set by nutritionist (kcal), used for progress bar and daily scoring
- **bmr**: Basal Metabolic Rate (kcal/day), used to calculate total calories burned
- **steps_goal**: Daily steps goal, used for daily metrics evaluation
- **hydration_goal**: Daily hydration goal (ml), used for daily metrics evaluation

**Notes:**
- All fields are nullable to allow gradual population
- These fields are set by nutritionists during patient profile setup (not in v1 scope)

### 3.2 Journals Table

**Migration**: `YYYYMMDDHHMMSS_create_journals.rb` (new)

```ruby
class CreateJournals < ActiveRecord::Migration[8.1]
  def change
    create_table :journals do |t|
      t.references :patient, null: false, foreign_key: { on_delete: :cascade }
      t.date :date, null: false
      t.timestamp :closed_at, null: true
      t.integer :calories_consumed, null: true
      t.integer :calories_burned, null: true
      t.integer :score, null: true
      t.text :feedback_positive, null: true
      t.text :feedback_improvement, null: true
      t.integer :feeling_today, null: true
      t.integer :sleep_quality, null: true
      t.integer :hydration_quality, null: true
      t.integer :steps_count, null: true
      t.text :daily_note, null: true

      t.timestamps
    end

    add_index :journals, :patient_id
    add_index :journals, :closed_at
    add_index :journals, [:patient_id, :date], unique: true, name: "journals_patient_date_unique_idx"
  end
end
```

**Field Descriptions:**
- **id**: Primary key, auto-incrementing integer
- **patient_id**: Foreign key to patients.id with CASCADE delete
- **date**: Journal date (DATE type, no time component)
- **closed_at**: Timestamp when day was closed (NULL if not closed)
- **calories_consumed**: Total calories from confirmed meals (calculated on closure)
- **calories_burned**: Total calories burned (BMR + confirmed exercises, calculated on closure)
- **score**: Daily score (1-5, calculated by LLM on closure)
- **feedback_positive**: "What went well" feedback from LLM (in user's language)
- **feedback_improvement**: "What to improve" feedback from LLM (in user's language)
- **feeling_today**: How patient felt about the plan (1=bad, 2=ok, 3=good)
- **sleep_quality**: Sleep quality last night (1=poor, 2=good, 3=excellent)
- **hydration_quality**: Hydration during the day (1=poor, 2=good, 3=excellent)
- **steps_count**: Daily steps count
- **daily_note**: Free text note from patient (optional)
- **created_at**: Timestamp when journal was created
- **updated_at**: Timestamp when journal was last modified

**Indexes:**
- Primary Key: `journals_pkey` on `id` (automatic)
- Index: `journals_patient_id_idx` on `patient_id` (for patient lookup)
- Unique Index: `journals_patient_date_unique_idx` on `(patient_id, date)` (ensures one journal per patient per date)
- Index: `journals_date_idx` on `date` (for date range queries)
- Index: `journals_closed_at_idx` on `closed_at` (for filtering closed/open days)

**Foreign Keys:**
- `patient_id` references `patients.id` with CASCADE delete

**Notes:**
- Journal is created automatically when first meal or exercise is logged for a date
- `date` is stored as DATE type (timezone handling done at application level)
- Unique constraint ensures one journal per patient per date

### 3.3 Meals Table

**Migration**: `YYYYMMDDHHMMSS_create_meals.rb` (new)

```ruby
class CreateMeals < ActiveRecord::Migration[8.1]
  def change
    create_table :meals do |t|
      t.references :journal, null: false, foreign_key: { on_delete: :cascade }
      t.string :meal_type, limit: 20, null: false
      t.string :description, limit: 140, null: false
      t.integer :proteins, null: true
      t.integer :carbs, null: true
      t.integer :fats, null: true
      t.integer :calories, null: true
      t.integer :gram_weight, null: true
      t.text :ai_comment, null: true
      t.integer :feeling, null: true
      t.string :status, limit: 20, null: false, default: 'pending_llm'

      t.timestamps
    end

    add_index :meals, :journal_id
    add_index :meals, [:journal_id, :status], name: 'meals_journal_status_idx'
    add_index :meals, :meal_type
  end
end
```

**Field Descriptions:**
- **id**: Primary key, auto-incrementing integer
- **journal_id**: Foreign key to journals.id with CASCADE delete
- **meal_type**: Meal type (breakfast, lunch, snack, dinner)
- **description**: Free text description of the meal (max 140 characters)
- **proteins**: Proteins in grams
- **carbs**: Carbohydrates in grams
- **fats**: Fats in grams
- **calories**: Calories in kcal
- **gram_weight**: Estimated total gram weight
- **ai_comment**: AI-generated comment about the meal (in user's language)
- **feeling**: Feeling indicator (1 = positive, 0 = negative)
- **status**: Status (pending_llm, pending_patient, confirmed), defaults to 'pending_llm'
- **created_at**: Timestamp when meal was created
- **updated_at**: Timestamp when meal was last modified

**Indexes:**
- Primary Key: `meals_pkey` on `id` (automatic)
- Index: `meals_journal_id_idx` on `journal_id` (for journal lookup)
- Composite Index: `meals_journal_status_idx` on `(journal_id, status)` (optimizes common queries: `journal.meals.where(status: ...)`)
- Index: `meals_meal_type_idx` on `meal_type` (for meal type queries)

**Foreign Keys:**
- `journal_id` references `journals.id` with CASCADE delete

**Notes:**
- `meal_type` is a fixed enum (not configurable in v1)
- `description` is limited to 140 characters
- `status` defaults to 'pending_llm' when user submits description

### 3.4 Exercises Table

**Migration**: `YYYYMMDDHHMMSS_create_exercises.rb` (new)

```ruby
class CreateExercises < ActiveRecord::Migration[8.1]
  def change
    create_table :exercises do |t|
      t.references :journal, null: false, foreign_key: { on_delete: :cascade }
      t.string :description, limit: 140, null: false
      t.integer :duration, null: true
      t.integer :calories, null: true
      t.integer :neat, null: true
      t.string :structured_description, limit: 255, null: true
      t.string :status, limit: 20, null: false, default: 'pending_llm'

      t.timestamps
    end

    add_index :exercises, :journal_id
    add_index :exercises, [:journal_id, :status], name: 'exercises_journal_status_idx'
  end
end
```

**Field Descriptions:**
- **id**: Primary key, auto-incrementing integer
- **journal_id**: Foreign key to journals.id with CASCADE delete
- **description**: Free text description of the exercise (max 140 characters)
- **duration**: Duration in minutes
- **calories**: Calories burned in kcal
- **neat**: NEAT (Non-Exercise Activity Thermogenesis) in kcal (0 if not applicable)
- **structured_description**: Structured description from LLM (e.g., "5 km moderate run")
- **status**: Status (pending_llm, pending_patient, confirmed), defaults to 'pending_llm'
- **created_at**: Timestamp when exercise was created
- **updated_at**: Timestamp when exercise was last modified

**Indexes:**
- Primary Key: `exercises_pkey` on `id` (automatic)
- Index: `exercises_journal_id_idx` on `journal_id` (for journal lookup)
- Composite Index: `exercises_journal_status_idx` on `(journal_id, status)` (optimizes common queries: `journal.exercises.where(status: ...)`)

**Foreign Keys:**
- `journal_id` references `journals.id` with CASCADE delete

**Notes:**
- `description` is limited to 140 characters
- `status` defaults to 'pending_llm' when user submits description

---

## 4. Rails Models

### 4.1 Patient Model (Extended)

**File**: `app/models/patient.rb`

```ruby
class Patient < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :professional # Uncomment when Professional model is created
  has_many :journals, dependent: :destroy

  # Validations
  validates :user_id, uniqueness: { scope: :professional_id, message: "already has a patient record for this professional" }
  validates :professional_id, presence: true
  
  # Journal-related validations
  validates :daily_calorie_goal, numericality: { greater_than: 0, less_than: 50000 }, allow_nil: true
  validates :bmr, numericality: { greater_than: 0, less_than: 10000 }, allow_nil: true
  validates :steps_goal, numericality: { greater_than: 0, less_than: 100000 }, allow_nil: true
  validates :hydration_goal, numericality: { greater_than: 0, less_than: 20000 }, allow_nil: true

  # Immutability: professional_id cannot be changed once set
  validate :professional_id_immutable, on: :update

  private

  def professional_id_immutable
    if professional_id_changed? && persisted?
      errors.add(:professional_id, "cannot be changed once set")
    end
  end
end
```

**Validations:**
- **professional_id**: Must be present and immutable once set (ensures data isolation)
- **daily_calorie_goal**: Must be positive and less than 50,000 kcal (if present)
- **bmr**: Must be positive and less than 10,000 kcal (if present)
- **steps_goal**: Must be positive and less than 100,000 steps (if present)
- **hydration_goal**: Must be positive and less than 20,000 ml (if present)

**Notes:**
- `professional_id` immutability is enforced at model level (defense in depth)
- Journal-related fields are nullable to allow gradual population

### 4.2 Journal Model

**File**: `app/models/journal.rb`

```ruby
class Journal < ApplicationRecord
  extend Enumerize

  # Associations
  belongs_to :patient
  has_many :meals, dependent: :destroy
  has_many :exercises, dependent: :destroy

  # Enumerize definitions (with i18n support)
  enumerize :feeling_today, in: { bad: 1, ok: 2, good: 3 }, default: nil, scope: true
  enumerize :sleep_quality, in: { poor: 1, good: 2, excellent: 3 }, default: nil, scope: true
  enumerize :hydration_quality, in: { poor: 1, good: 2, excellent: 3 }, default: nil, scope: true

  # Scopes
  scope :closed, -> { where.not(closed_at: nil) }
  scope :open, -> { where(closed_at: nil) }
  scope :for_date, ->(date) { where(date: date) }
  scope :recent, -> { order(date: :desc) }

  # Validations
  validates :date, presence: true
  validates :patient_id, presence: true
  validates :score, inclusion: { in: 1..5 }, allow_nil: true
  validates :steps_count, numericality: { greater_than_or_equal_to: 0, less_than: 100000 }, allow_nil: true
  validates :calories_consumed, numericality: { greater_than_or_equal_to: 0, less_than: 50000 }, allow_nil: true
  validates :calories_burned, numericality: { greater_than_or_equal_to: 0, less_than: 50000 }, allow_nil: true

  # Uniqueness: one journal per patient per date
  validates :date, uniqueness: { scope: :patient_id, message: "already has a journal entry for this date" }

  # Business Logic
  def closed?
    closed_at.present?
  end

  def open?
    closed_at.nil?
  end

  def editable?
    return false unless closed?
    # Can edit closed days up to 2 days after journal date
    Date.current <= date + 2.days
  end

  def confirmed_meals
    meals.status_confirmed
  end

  def confirmed_exercises
    exercises.status_confirmed
  end

  def pending_meals
    meals.pending
  end

  def pending_exercises
    exercises.pending
  end

  def has_pending_entries?
    pending_meals.exists? || pending_exercises.exists?
  end

  def calculate_calories_consumed
    confirmed_meals.sum(:calories) || 0
  end

  def calculate_calories_burned
    return 0 unless patient.bmr
    patient.bmr + confirmed_exercises.sum(:calories)
  end

  def calculate_balance
    calculate_calories_consumed - calculate_calories_burned
  end
end
```

**Validations:**
- **date**: Must be present and unique per patient
- **score**: Must be between 1 and 5 (if present)
- **feeling_today**: Validated via Enumerize (1=bad, 2=ok, 3=good) (if present)
- **sleep_quality**: Validated via Enumerize (1=poor, 2=good, 3=excellent) (if present)
- **hydration_quality**: Validated via Enumerize (1=poor, 2=good, 3=excellent) (if present)

**Enumerize Integration:**
- Uses `enumerize` gem for enum management with i18n support
- Values stored as integers (1, 2, 3) in database
- Labels translated via Rails i18n (e.g., `en.journal.feeling_today.bad`, `en.journal.feeling_today.ok`, `en.journal.feeling_today.good`)
- Provides helper methods: `feeling_today_bad?`, `feeling_today_ok?`, `feeling_today_good?`, etc.
- Provides scopes: `Journal.feeling_today_bad`, `Journal.sleep_quality_excellent`, etc.
- Allows future expansion to 1-5 scale by updating enumerize definition
- **steps_count**: Must be non-negative and less than 100,000 (if present)
- **calories_consumed**: Must be non-negative and less than 50,000 (if present)
- **calories_burned**: Must be non-negative and less than 50,000 (if present)

**Business Logic:**
- `closed?`: Returns true if day is closed
- `open?`: Returns true if day is not closed
- `editable?`: Returns true if closed day can still be edited (within 2 days of journal date)
- `confirmed_meals`: Returns confirmed meals only
- `confirmed_exercises`: Returns confirmed exercises only
- `pending_meals`: Returns pending meals only
- `pending_exercises`: Returns pending exercises only
- `has_pending_entries?`: Returns true if there are any pending entries
- `calculate_calories_consumed`: Calculates total calories from confirmed meals
- `calculate_calories_burned`: Calculates total calories burned (BMR + confirmed exercises)
- `calculate_balance`: Calculates daily caloric balance

**Notes:**
- Journal is created automatically when first meal or exercise is logged
- Date uniqueness is enforced at database level (unique index) and model level (validation)
- Enumerize provides type-safe enum handling with i18n support
- Values are stored as integers (1, 2, 3) but accessed via symbolic names (bad, ok, good, etc.)

### 4.3 Meal Model

**File**: `app/models/meal.rb`

```ruby
class Meal < ApplicationRecord
  extend Enumerize

  # Associations
  belongs_to :journal

  # Constants
  MEAL_TYPES = %w[breakfast lunch snack dinner].freeze
  FEELING_POSITIVE = 1
  FEELING_NEGATIVE = 0

  # Enumerize definitions (with i18n support)
  enumerize :status, in: { pending_llm: 'pending_llm', pending_patient: 'pending_patient', confirmed: 'confirmed' }, default: 'pending_llm', scope: true

  # Validations
  validates :meal_type, presence: true, inclusion: { in: MEAL_TYPES }
  validates :description, presence: true, length: { maximum: 140 }
  validates :proteins, numericality: { greater_than_or_equal_to: 0, less_than: 10000 }, allow_nil: true
  validates :carbs, numericality: { greater_than_or_equal_to: 0, less_than: 10000 }, allow_nil: true
  validates :fats, numericality: { greater_than_or_equal_to: 0, less_than: 10000 }, allow_nil: true
  validates :calories, numericality: { greater_than: 0, less_than: 50000 }, allow_nil: true
  validates :gram_weight, numericality: { greater_than: 0, less_than: 100000 }, allow_nil: true
  validates :feeling, inclusion: { in: [FEELING_POSITIVE, FEELING_NEGATIVE] }, allow_nil: true

  # Scopes
  scope :pending, -> { where(status: ['pending_llm', 'pending_patient']) }
  scope :by_meal_type, ->(type) { where(meal_type: type) }

  # Business Logic
  def pending?
    ['pending_llm', 'pending_patient'].include?(status)
  end

  def feeling_positive?
    feeling == FEELING_POSITIVE
  end

  def confirm!
    update!(status: :confirmed)
  end

  def mark_as_pending_patient!
    update!(status: :pending_patient)
  end

  def reprocess_with_ai!
    update!(status: :pending_llm)
  end
end
```

**Validations:**
- **meal_type**: Must be one of: breakfast, lunch, snack, dinner
- **description**: Must be present and maximum 140 characters
- **status**: Validated via Enumerize (pending_llm, pending_patient, confirmed)
- **proteins**: Must be non-negative and less than 10,000 g (if present)
- **carbs**: Must be non-negative and less than 10,000 g (if present)
- **fats**: Must be non-negative and less than 10,000 g (if present)
- **calories**: Must be positive and less than 50,000 kcal (if present)
- **gram_weight**: Must be positive and less than 100,000 g (if present)
- **feeling**: Must be 1 (positive) or 0 (negative) (if present)

**Business Logic:**
- `confirmed?`: Returns true if meal is confirmed (provided by Enumerize)
- `pending_llm?`: Returns true if meal is awaiting LLM response (provided by Enumerize)
- `pending_patient?`: Returns true if meal is awaiting user confirmation (provided by Enumerize)
- `pending?`: Returns true if meal is in any pending state (pending_llm or pending_patient)
- `feeling_positive?`: Returns true if feeling is positive
- `confirm!`: Confirms the meal (sets status to 'confirmed')
- `mark_as_pending_patient!`: Marks meal as awaiting user confirmation (after LLM response)
- `reprocess_with_ai!`: Resets status to pending_llm for AI reprocessing

**Notes:**
- Meal types are fixed (not configurable in v1)
- Status defaults to 'pending_llm' when user submits description (via Enumerize default)
- Enumerize provides helper methods (`confirmed?`, `pending_llm?`, `pending_patient?`) and scopes (`Meal.status_confirmed`, `Meal.status_pending_llm`, etc.)
- Status values are stored as strings in database but accessed via symbols (e.g., `:pending_llm`)

### 4.4 Exercise Model

**File**: `app/models/exercise.rb`

```ruby
class Exercise < ApplicationRecord
  extend Enumerize

  # Associations
  belongs_to :journal

  # Enumerize definitions (with i18n support)
  enumerize :status, in: { pending_llm: 'pending_llm', pending_patient: 'pending_patient', confirmed: 'confirmed' }, default: 'pending_llm', scope: true

  # Validations
  validates :description, presence: true, length: { maximum: 140 }
  validates :duration, numericality: { greater_than: 0, less_than: 1440 }, allow_nil: true # max 24 hours
  validates :calories, numericality: { greater_than_or_equal_to: 0, less_than: 10000 }, allow_nil: true
  validates :neat, numericality: { greater_than_or_equal_to: 0, less_than: 5000 }, allow_nil: true

  # Scopes
  scope :pending, -> { where(status: ['pending_llm', 'pending_patient']) }

  # Business Logic
  def pending?
    ['pending_llm', 'pending_patient'].include?(status)
  end

  def confirm!
    update!(status: :confirmed)
  end

  def mark_as_pending_patient!
    update!(status: :pending_patient)
  end

  def reprocess_with_ai!
    update!(status: :pending_llm)
  end
end
```

**Validations:**
- **description**: Must be present and maximum 140 characters
- **status**: Validated via Enumerize (pending_llm, pending_patient, confirmed)
- **duration**: Must be positive and less than 1440 minutes (24 hours) (if present)
- **calories**: Must be non-negative and less than 10,000 kcal (if present)
- **neat**: Must be non-negative and less than 5,000 kcal (if present)

**Business Logic:**
- `confirmed?`: Returns true if exercise is confirmed (provided by Enumerize)
- `pending_llm?`: Returns true if exercise is awaiting LLM response (provided by Enumerize)
- `pending_patient?`: Returns true if exercise is awaiting user confirmation (provided by Enumerize)
- `pending?`: Returns true if exercise is in any pending state (pending_llm or pending_patient)
- `confirm!`: Confirms the exercise (sets status to 'confirmed')
- `mark_as_pending_patient!`: Marks exercise as awaiting user confirmation (after LLM response)
- `reprocess_with_ai!`: Resets status to pending_llm for AI reprocessing

**Notes:**
- Status defaults to 'pending_llm' when user submits description (via Enumerize default)
- Enumerize provides helper methods (`confirmed?`, `pending_llm?`, `pending_patient?`) and scopes (`Exercise.status_confirmed`, `Exercise.status_pending_llm`, etc.)
- Status values are stored as strings in database but accessed via symbols (e.g., `:pending_llm`)

---

## 5. LLM Integration Architecture

### 5.1 Interaction Structure

**File**: `app/interactions/journal/analyze_meal_interaction.rb`

```ruby
module Journal
  class AnalyzeMealInteraction < ActiveInteraction::Base
    string :description
    string :meal_type
    string :user_language, default: 'pt'
    object :meal, class: Meal

    validates :description, presence: true, length: { maximum: 140 }
    validates :meal_type, inclusion: { in: Meal::MEAL_TYPES }
    validates :user_language, presence: true

    def execute
      # Check rate limits
      return errors.add(:base, rate_limit_error) unless rate_limit_ok?

      # Call LLM via ruby_llm
      result = call_llm_for_meal_analysis

      # Parse and validate response
      return nil unless result

      # Update meal with LLM response
      update_meal_with_analysis(result)
    end

    private

    def rate_limit_ok?
      # Check user rate limits (50/day, 10/hour)
    end

    def call_llm_for_meal_analysis
      # Use ruby_llm to call OpenAI
      # Handle retries, errors, etc.
    end

    def update_meal_with_analysis(result)
      # Update meal with parsed LLM response
      # Set status to pending_patient
    end

    def rate_limit_error
      I18n.t('journal.errors.rate_limit_exceeded', locale: user_language)
    end
  end
end
```

**File**: `app/interactions/journal/analyze_exercise_interaction.rb`

```ruby
module Journal
  class AnalyzeExerciseInteraction < ActiveInteraction::Base
    string :description
    string :user_language, default: 'pt'
    object :exercise, class: Exercise

    validates :description, presence: true, length: { maximum: 140 }
    validates :user_language, presence: true

    def execute
      # Similar structure to AnalyzeMealInteraction
    end
  end
end
```

**File**: `app/interactions/journal/score_daily_journal_interaction.rb`

```ruby
module Journal
  class ScoreDailyJournalInteraction < ActiveInteraction::Base
    object :journal, class: Journal
    string :user_language, default: 'pt'

    validates :journal, presence: true
    validates :user_language, presence: true

    def execute
      # Check journal is closed
      return errors.add(:journal, :not_closed) unless journal.closed?

      # Build prompt with daily context
      prompt = build_daily_scoring_prompt

      # Call LLM via ruby_llm
      result = call_llm_for_daily_scoring(prompt)

      # Parse and update journal
      update_journal_with_score(result)
    end

    private

    def build_daily_scoring_prompt
      # Build prompt from journal data, patient goals, scoring criteria
    end

    def call_llm_for_daily_scoring(prompt)
      # Use ruby_llm with structured output schema
    end

    def update_journal_with_score(result)
      # Update journal with score, feedback_positive, feedback_improvement
    end
  end
end
```

**Required Gems** - Add to `Gemfile`:
```ruby
gem 'active_interaction', '~> 5.0'  # Already in use (Auth module)
gem 'ruby_llm', '~> 0.1'           # LLM abstraction layer
```

**Notes:**
- Interactions handle all LLM operations with business logic
- `ruby_llm` gem handles low-level API communication, retries, etc.
- Rate limiting, validation, and error handling in interactions
- Easy to test by mocking `ruby_llm` calls
- Can be called from controllers, background jobs, rake tasks

### 5.2 Prompt Templates

**Meal Analysis Prompt:**

```
Analyze meal description and return nutrition data.

Lang: {user_language}
Type: {meal_type}
Description: "{meal_description}"

Return JSON:
- p: proteins (g)
- c: carbs (g)
- f: fats (g)
- cal: calories (kcal)
- gw: weight (g)
- cmt: brief comment ({user_language}, 2-3 sentences)
- feel: 1 if nutritionally good/balanced, 0 if not ideal

{
  "p": <number>,
  "c": <number>,
  "f": <number>,
  "cal": <number>,
  "gw": <number>,
  "cmt": "<text>",
  "feel": <1 or 0>
}
```

**Exercise Analysis Prompt:**

```
Analyze exercise description and return metrics.

Lang: {user_language}
Description: "{exercise_description}"

Return JSON:
- d: duration (minutes)
- cal: calories burned (kcal)
- n: NEAT (kcal, 0 if not applicable)
- sd: structured description ({user_language}, e.g., "5 km moderate run")

{
  "d": <number>,
  "cal": <number>,
  "n": <number>,
  "sd": "<text>"
}
```

**Daily Scoring Prompt:**

See PRD Section 9.5 for full prompt template. Key components:
- User language
- Patient goals (daily_calorie_goal, bmr, steps_goal, hydration_goal)
- Daily metrics (feeling_today, sleep_quality, hydration_quality, steps_count, daily_note)
- Confirmed meals summary (pipe-separated format)
- Confirmed exercises summary (pipe-separated format)
- Weekly context variables
- Scoring criteria (from seed data, see section 6)

### 5.3 Error Handling

**LLM Failures:**
- Show clear, user-friendly error messages in user's language
- Display "Retry" button to attempt LLM call again
- Log errors with context for debugging
- Automatic retry with exponential backoff (max 3 retries) for transient failures

**Rate Limiting:**
- Maximum 50 LLM calls per user per day
- Maximum 10 LLM calls per user per hour
- Show appropriate error message when rate limit is exceeded

**Response Validation:**
- Validate JSON structure
- Validate value ranges (e.g., calories > 0 and < 50,000)
- Handle malformed responses gracefully

---

## 6. Scoring Criteria Seed Data

### 6.1 Seed Structure

For v1, scoring criteria templates will be provided via seed data. Each template is based on patient profile (obesity level, gender, weight loss goal).

**File**: `db/seeds/scoring_criteria.rb`

```ruby
# Scoring criteria templates for different patient profiles
# These will be used in LLM prompts for daily scoring

SCORING_CRITERIA_TEMPLATES = {
  obese_female: {
    min_protein: 80,
    max_protein: 120,
    template: <<~TEMPLATE
      Balance caloric deficit with nutritional adequacy, exercise appropriateness, and sustainable habits.
      
      Scoring criteria:
      SCORE 5
      - Caloric balance: Within -200 and +100 kcal of daily goal (considering BMR + exercise)
      - Protein: Within 80g - 120g range
      - 2 meals with fruit
      - 2 meals with vegetable servings
      - Exercise: Present today with light-moderate intensity (appropriate for obese patients)
      - Meal quality: All meals nutritionally balanced
      - Sleep: Excellent quality
      - Hydration: Excellent (meeting daily goal)
      - Steps: Meeting daily goal
      - No candy
      
      [Additional score levels...]
      
      EXERCISE INTENSITY GUARDRAILS:
      - Obese patients (BMI >30): Prefer light-moderate intensity. High intensity exercises should reduce score. Start gradual.
      
      QUALITY OF LIFE PRIORITIES:
      1. Prevent extreme caloric restriction that may cause muscle loss, fatigue, or metabolic issues
      2. Ensure adequate protein to preserve muscle during weight loss
      [Additional priorities...]
    TEMPLATE
  },
  # Additional templates for other patient profiles...
}
```

**Notes:**
- Templates are stored as seed data (not in database)
- Selected based on patient profile during daily scoring
- In future versions, these will be configurable per nutritionist per patient

---

## 7. Timezone & Language Handling

### 7.1 Timezone Handling

**Application Level:**
- All date calculations use `user.timezone` (stored in `users.timezone`)
- Date boundaries are calculated based on user's timezone
- Journal `date` field is stored as DATE type (no time component)
- Timezone conversion happens at application level (via ApplicationController)

**Example:**
- User in `America/Sao_Paulo` timezone logs entry at 23:30 on Jan 14
- Entry at 00:30 on Jan 15 belongs to Jan 15 (next day in user's timezone)
- Journal `date` is stored as `2026-01-15` (DATE type)

**Implementation:**
- Use `Time.zone = user.timezone` in ApplicationController
- Use `Date.current` (timezone-aware) instead of `Date.today`
- Convert user input dates to user's timezone before storing

### 7.2 Language Handling

**LLM Interactions:**
- All prompts include `user.language` parameter
- All LLM responses are expected in `user.language`
- Error messages are shown in `user.language`
- UI translations use `user.language` (via Rails i18n)

**Implementation:**
- Pass `user.language` to all LLM service methods
- Include language instruction in all prompt templates
- Use Rails i18n for UI translations

**Enumerize i18n Translations:**
- Enumerize values are translated via Rails i18n
- Translation keys follow pattern: `{locale}.journal.{field}.{value}`
- Example structure for `config/locales/pt.yml`:
  ```yaml
  pt:
    journal:
      feeling_today:
        bad: "Ruim"
        ok: "Ok"
        good: "Bom"
      sleep_quality:
        poor: "Ruim"
        good: "Bom"
        excellent: "Excelente"
      hydration_quality:
        poor: "Ruim"
        good: "Bom"
        excellent: "Excelente"
    meal:
      status:
        pending_llm: "Aguardando IA"
        pending_patient: "Aguardando Paciente"
        confirmed: "Confirmado"
    exercise:
      status:
        pending_llm: "Aguardando IA"
        pending_patient: "Aguardando Paciente"
        confirmed: "Confirmado"
  ```
- Access translations: `journal.feeling_today.text`, `meal.status.text`, `exercise.status.text` (returns translated label)
- Helper methods: `journal.feeling_today_bad?`, `meal.status_confirmed?`, `exercise.status_pending_llm?`, etc.
- Scopes: `Meal.status_confirmed`, `Meal.status_pending_llm`, `Exercise.status_pending_patient`, etc.

---

## 8. Business Rules & Validations

### 8.1 Journal Creation

- Journal is created automatically when first meal or exercise is logged for a date
- One journal per patient per date (enforced by unique index)
- Journal `date` is determined by user's timezone

### 8.2 Status Workflow

**Meals & Exercises:**
- **Status workflow**:
  - `pending_llm`: Created when user submits description, awaiting LLM response
  - `pending_patient`: LLM response received, awaiting user confirmation (shown in review screen)
  - `confirmed`: User confirmed the entry (either accepted as-is or after manual adjustments)
- User can accept (confirm), edit values, or reprocess with AI (reprocess sets status back to `pending_llm`)
- Only `confirmed` entries are counted in daily totals
- Users can edit or delete confirmed entries (status remains `confirmed`)
- All `pending_llm` and `pending_patient` entries are deleted when journal day is closed

### 8.3 Daily Closure

**Before Closure:**
- User must answer daily metrics questions:
  - How are you feeling about the plan? (1=bad, 2=ok, 3=good)
  - Sleep quality last night? (1=poor, 2=good, 3=excellent)
  - Hydration during the day? (1=poor, 2=good, 3=excellent)
  - Daily steps count? (numeric)
  - Free text note? (optional)

**During Closure:**
- All `pending_llm` and `pending_patient` entries are automatically deleted
- Daily totals are calculated from confirmed entries only:
  - `calories_consumed` = sum of confirmed meals calories
  - `calories_burned` = BMR + sum of confirmed exercises calories
- LLM is called with daily context to generate score and feedback
- `closed_at` timestamp is set

**After Closure:**
- Closed days can be edited up to 2 days after journal date
- After 2 days, closed days become read-only
- Editing a closed day does not reset `closed_at` (day remains closed)

### 8.4 Data Isolation

- All journal data is isolated per professional via `patient.professional_id`
- `patient.professional_id` is immutable once set (enforced at model level)
- Nutritionists can view the same journal view as patients (read-only access)
- Data access is filtered by `patient.professional_id` in all queries

### 8.5 Value Ranges

**Meals:**
- Proteins, carbs, fats: 0 to 10,000 g
- Calories: > 0 and < 50,000 kcal
- Gram weight: > 0 and < 100,000 g

**Exercises:**
- Duration: > 0 and < 1440 minutes (24 hours)
- Calories: 0 to 10,000 kcal
- NEAT: 0 to 5,000 kcal

**Journals:**
- Calories consumed: 0 to 50,000 kcal
- Calories burned: 0 to 50,000 kcal
- Steps count: 0 to 100,000 steps
- Score: 1 to 5

---

## 9. Indexes & Performance

### 9.1 Critical Indexes

**Journals:**
- `journals_patient_id_idx`: For patient lookup
- `journals_patient_date_unique_idx`: Unique constraint + optimizes queries filtering by patient and date (covers date range queries per patient)
- `journals_closed_at_idx`: For filtering closed/open days

**Meals:**
- `meals_journal_id_idx`: For journal lookup
- `meals_journal_status_idx`: Composite index on `(journal_id, status)` - optimizes most common queries filtering by journal and status (e.g., `journal.confirmed_meals`, `journal.pending_meals`)
- `meals_meal_type_idx`: For meal type queries
- **Note**: If global queries by status alone become frequent (e.g., `Meal.where(status: 'pending_patient')`), consider adding a simple index on `status` as well

**Exercises:**
- `exercises_journal_id_idx`: For journal lookup
- `exercises_journal_status_idx`: Composite index on `(journal_id, status)` - optimizes most common queries filtering by journal and status (e.g., `journal.confirmed_exercises`, `journal.pending_exercises`)
- **Note**: If global queries by status alone become frequent, consider adding a simple index on `status` as well

**Patients:**
- `patients_professional_id_idx`: For professional lookup (data isolation)

### 9.2 Query Patterns

**Common Queries:**
1. Get journal for patient and date: `Journal.where(patient_id: X, date: Y).first`
2. Get confirmed meals for journal: `journal.confirmed_meals`
3. Get pending entries for journal: `journal.pending_meals + journal.pending_exercises`
4. Get journals for patient (date range): `patient.journals.where(date: start_date..end_date)`
5. Get closed journals for patient: `patient.journals.closed`

**Performance Considerations:**
- All common queries are covered by indexes
- Journal creation is automatic (no extra query needed)
- Daily totals are calculated on-demand (not stored until closure)

---

## 10. Future Considerations (Out of Scope v1)

### 10.1 Deferred Features

- **LLM Response Caching**: Caching strategy deferred to future versions
- **Background Jobs**: LLM calls are synchronous in v1 (can be moved to background jobs later)
- **Configurable Scoring Criteria**: Scoring criteria will be configurable per nutritionist per patient in future versions
- **Multi-nutritionist Workflows**: One patient per professional in v1
- **Advanced Analytics**: Cohort dashboards and advanced analytics deferred
- **Device Integrations**: Smartwatch and health API integrations deferred
- **Image Processing**: Meal/exercise image analysis deferred
- **Duplicate Detection**: Duplicate meal detection and merging deferred

### 10.2 Potential Optimizations

- **Caching**: Cache LLM responses for similar meal descriptions
- **Background Processing**: Move LLM calls to background jobs for better UX
- **Batch Operations**: Batch daily closure operations for multiple days
- **Materialized Views**: Create materialized views for weekly context calculations

---

## 11. Testing Considerations

### 11.1 Model Tests

- Test all validations (value ranges, enums, presence)
- Test business logic methods (confirmed?, editable?, calculate methods)
- Test associations and cascading deletes
- Test immutability constraints (professional_id)

### 11.2 Interaction Tests

- Test LLM interaction methods (meal analysis, exercise analysis, daily scoring)
- Test input validation (ActiveInteraction built-in)
- Test error handling and retry logic
- Test rate limiting
- Mock `ruby_llm` calls for consistent testing
- Test business logic separately from LLM API calls

### 11.3 Integration Tests

- Test journal creation flow
- Test meal/exercise confirmation flow
- Test daily closure flow
- Test pending entry cleanup
- Test timezone handling
- Test language handling

---

## 12. Migration Order

1. Add journal fields to patients table (`add_journal_fields_to_patients`)
2. Create journals table (`create_journals`)
3. Create meals table (`create_meals`)
4. Create exercises table (`create_exercises`)

**Dependencies:**
- Journals depend on patients (already exists)
- Meals and exercises depend on journals

---

## 13. Implementation Plan

This implementation plan breaks down the Journal module development into 5 phases, each delivered as a separate PR using the `/build-task` command.

**Branch Naming Convention**: `BAL-XX.pY` where `XX` is the Linear issue ID and `Y` is the phase number.

**Workflow**: Each phase follows the `/build-task` workflow:
1. Branch setup from main
2. Implementation
3. Verification (code compiles, tests pass, migrations work)
4. Code review
5. Apply feedback and commit
6. Create PR
7. Update implementation plan status

---

### Phase 1: UI Prototyping with Mock Data

**Status**: ✅ **Complete** (Loading states deferred)

**Objective**: Create all UI screens with mock data before implementing backend logic. This allows for early UI/UX validation and ensures the frontend structure is solid before backend integration.

**Scope**:
- ✅ Daily Journal view (main screen)
- ✅ Meal entry form
- ✅ Meal review screen (pending_patient state)
- ✅ Exercise entry form
- ✅ Exercise review screen (pending_patient state)
- ✅ Daily closure modal/form
- ✅ Date navigator component
- ✅ Empty states for all screens

**Acceptance Criteria**:
- [x] All UI screens are implemented with mock data
- [x] Navigation between screens works correctly
- [x] Date navigator allows switching between dates
- [x] Empty states are shown when no data exists
- [x] All UI components are responsive
- [x] Forms have proper validation feedback (client-side) - Character counter implemented
- [⏸️] Loading states are implemented (spinners, skeletons) - **DEFERRED**
- [x] Error states are implemented (error messages, retry buttons)
- [x] UI matches design requirements from PRD (TailwindCSS + Flowbite)
- [x] No backend API calls (all data is mocked)

**Implementation Status**:
- ✅ **Views**: 12 files implemented
  - `journals/show.html.slim` - Main daily journal view
  - `journals/close.html.slim` - Daily closure form
  - `journals/_daily_summary.html.slim` - Summary partial
  - `journals/_date_navigator.html.slim` - Date navigator partial
  - `journals/_section.html.slim` - Generic section partial (with empty states)
  - `journal/meals/new.html.slim` - Meal entry form
  - `journal/meals/show.html.slim` - Meal review screen
  - `journal/meals/edit.html.slim` - Meal edit form
  - `journal/meals/_meal.html.slim` - Meal card partial
  - `journal/exercises/new.html.slim` - Exercise entry form
  - `journal/exercises/show.html.slim` - Exercise review screen
  - `journal/exercises/edit.html.slim` - Exercise edit form
  - `journal/exercises/_exercise.html.slim` - Exercise card partial

- ✅ **Controllers**: 3 controllers with mock data
  - `JournalsController` - Mock journal data with various states
  - `Journal::MealsController` - Mock meal data
  - `Journal::ExercisesController` - Mock exercise data

- ✅ **Helpers**: 1 helper file
  - `JournalHelper` - Date formatting, calculations, status formatting

- ✅ **JavaScript/Stimulus**: 2 controllers
  - `date_navigator_controller.js` - Date navigation functionality
  - `character_counter_controller.js` - Form character counting

- ✅ **CSS**: TailwindCSS configured and used throughout

**Deferred Items**:
- ⏸️ Loading states (spinners/skeletons) - Deferred to future iteration

**Estimated Files**:
- Views: ~15 files
- Controllers: ~5 files (with mock data methods)
- Helpers: ~3 files
- JavaScript/Stimulus: ~5 files
- CSS/SCSS: ~3 files

**Estimated Lines**: ~2,500 lines

**Dependencies**: None (can start immediately)

**Notes**:
- Use hardcoded mock data in controllers
- Mock data should represent all possible states (pending_llm, pending_patient, confirmed)
- Include edge cases in mock data (empty journal, many meals, closed days, etc.)

---

### Phase 2: Daily Journal Backend & Frontend Integration

**Status**: ✅ **Complete**

**Objective**: Implement the backend for the daily journal view and integrate with the frontend. Use seed data for initial testing.

**Scope**:
- Database migrations (journals, meals, exercises tables)
- Rails models (Journal, Meal, Exercise) with validations
- Journal controller with date navigation
- Daily journal view integration
- Seed data for testing
- Timezone handling
- Date boundary calculations

**Acceptance Criteria**:
- [x] All migrations are created and tested (up/down)
- [x] Journal, Meal, and Exercise models are implemented with all validations
- [x] Journal controller handles date navigation correctly
- [x] Daily journal view displays real data from database
- [x] Date navigator works with timezone-aware dates
- [x] Empty states show when no journal exists for a date
- [x] Seed data includes various scenarios (multiple days, meals, exercises)
- [x] All model tests pass
- [x] All controller tests pass
- [x] Timezone handling is tested

**Implementation Status**:
- ✅ Database and domain layer delivered
  - Migrations created for `patients` extension, `journals`, `meals`, and `exercises`
  - Models `Journal`, `Meal`, and `Exercise` implemented with validations, status handling, and helper methods
  - Enumerize used for journal qualitative fields and entry statuses
- ✅ Seed data delivered
  - Idempotent seed for Journal Phase 2 in pt-BR (`db/seeds/todays_journal_pt.rb`)
  - Seed flow wired through `db/seeds.rb`
- ✅ Daily Journal integration delivered
  - `JournalsController` integrated with persisted data and timezone-aware date navigation
  - Daily summary and journal sections render from database records instead of mock data
  - Authorization guard for authenticated users without patient record (`403`)
- ✅ Test coverage delivered
  - Model and controller specs covering data loading, isolation by patient/professional context, and timezone boundaries
  - Fixture + factory fallback strategy for journal-centric controller tests
- ✅ CI and reliability adjustments delivered
  - Controller namespace collision fixed for CI eager loading (`JournalEntries::*`)
  - Test workflow updated to install JS dependencies and precompile assets before specs

**Estimated Files**:
- Migrations: 4 files
- Models: 3 files
- Controllers: 1 file
- Views: 1 file (update from Phase 1)
- Seeds: 1 file
- Tests: ~15 files

**Estimated Lines**: ~3,000 lines

**Dependencies**: Phase 1 (UI structure)

**Notes**:
- Seed data should include multiple patients, journals for different dates
- Test timezone edge cases (day boundaries)
- Ensure data isolation via professional_id

---

### Phase 3: Meal Entry Backend & Frontend Integration

**Status**: ✅ **Completed**

**Objective**: Implement meal entry flow with LLM integration. Users can create meals, receive AI analysis, and confirm/edit entries.

**Scope**:
- Meal creation controller actions
- Journal auto-creation logic
- `Journal::AnalyzeMealInteraction` (using ruby_llm)
- Meal review screen integration
- Meal confirmation/edit flow
- Status workflow (pending_llm → pending_patient → confirmed)
- Rate limiting implementation
- Error handling for LLM failures

**Acceptance Criteria**:
- [x] Users can create meals with description and meal_type
- [x] Journal is auto-created when first meal is logged
- [x] LLM interaction analyzes meal and updates status to pending_patient
- [x] Meal review screen shows LLM analysis results
- [x] Users can confirm meals (status → confirmed)
- [x] Users can edit meal values before confirming
- [x] Users can reprocess with AI (status → pending_llm)
- [x] Rate limiting is enforced (50/day, 10/hour)
- [x] LLM errors are handled gracefully with retry option
- [x] All interaction tests pass
- [x] All controller tests pass
- [x] Integration tests for meal flow pass

**Estimated Files**:
- Interactions: 1 file
- Controllers: 1 file (update)
- Views: 2 files (update from Phase 1)
- Tests: ~8 files

**Estimated Lines**: ~2,000 lines

**Dependencies**: Phase 2 (models and database)

**Notes**:
- Mock ruby_llm calls in tests
- Implement retry logic with exponential backoff
- Validate LLM response structure and ranges
- Implemented via `Journal::AnalyzeMealInteraction` + `Journal::MealAnalysisClient` (wrapper-friendly for LLM provider mocking)

---

### Phase 4: Exercise Entry Backend & Frontend Integration

**Status**: ✅ **Completed**

**Objective**: Implement exercise entry flow with LLM integration. Similar to meal flow but for exercises.

**Scope**:
- Exercise creation controller actions
- `Journal::AnalyzeExerciseInteraction` (using ruby_llm)
- Exercise review screen integration
- Exercise confirmation/edit flow
- Status workflow (pending_llm → pending_patient → confirmed)
- Rate limiting (shared with meals)
- Error handling for LLM failures

**Acceptance Criteria**:
- [x] Users can create exercises with description
- [x] Journal is auto-created when first exercise is logged (if no journal exists)
- [x] LLM interaction analyzes exercise and updates status to pending_patient
- [x] Exercise review screen shows LLM analysis results
- [x] Users can confirm exercises (status → confirmed)
- [x] Users can edit exercise values before confirming
- [x] Users can reprocess with AI (status → pending_llm)
- [x] Rate limiting is shared with meals (total 50/day, 10/hour)
- [x] LLM errors are handled gracefully with retry option
- [x] All interaction tests pass
- [x] All controller tests pass
- [x] Integration tests for exercise flow pass

**Estimated Files**:
- Interactions: 1 file
- Controllers: 1 file (update)
- Views: 2 files (update from Phase 1)
- Tests: ~8 files

**Estimated Lines**: ~2,000 lines

**Dependencies**: Phase 3 (LLM integration pattern established)

**Notes**:
- Reuse rate limiting logic from Phase 3
- Follow same error handling patterns as meals

---

### Phase 5: Daily Closure Backend & Frontend Integration

**Status**: ✅ **Completed**

**Objective**: Implement daily closure flow with metrics collection and LLM scoring.

**Scope**:
- Daily metrics collection (feeling_today, sleep_quality, hydration_quality, steps_count, daily_note)
- Daily closure controller action
- Pending entries cleanup (delete pending_llm and pending_patient entries)
- Daily totals calculation (calories_consumed, calories_burned)
- `Journal::ScoreDailyJournalInteraction` (using ruby_llm)
- Daily scoring prompt building
- Score and feedback display
- Editable closed days (up to 2 days after journal date)
- Read-only closed days (after 2 days)

**Acceptance Criteria**:
- [x] Users can answer daily metrics questions before closure
- [x] Daily closure deletes all pending_llm and pending_patient entries
- [x] Daily totals are calculated from confirmed entries only
- [x] LLM interaction generates score (1-5) and feedback
- [x] Score and feedback are displayed on closed journal
- [x] Closed days can be edited up to 2 days after journal date
- [x] Closed days become read-only after 2 days
- [x] Editing closed day doesn't reset closed_at
- [x] All interaction tests pass
- [x] All controller tests pass
- [x] Integration tests for closure flow pass
- [x] Edge cases are tested (no meals, no exercises, etc.)

**Estimated Files**:
- Interactions: 1 file
- Controllers: 1 file (update)
- Views: 2 files (update from Phase 1)
- Seeds: 1 file (update with scoring criteria)
- Tests: ~10 files

**Estimated Lines**: ~2,500 lines

**Dependencies**: Phase 4 (all entry flows complete)

**Notes**:
- Scoring criteria templates are in seed data
- Test various scenarios (perfect day, bad day, mixed day)
- Ensure LLM prompt includes all required context

---

### Phase Summary

| Phase | Description | Status | Dependencies |
|-------|-------------|--------|--------------|
| 1 | UI Prototyping | ✅ Complete | None |
| 2 | Daily Journal Backend | ✅ Complete | Phase 1 |
| 3 | Meal Entry | ✅ Complete | Phase 2 |
| 4 | Exercise Entry | ✅ Complete | Phase 3 |
| 5 | Daily Closure | ✅ Complete | Phase 4 |

**Total Estimated Files**: ~80 files
**Total Estimated Lines**: ~12,000 lines

---

## 14. Summary

This ERD defines the complete data model for the Journal module, including:

- **3 new tables**: `journals`, `meals`, `exercises`
- **4 new fields on patients**: `daily_calorie_goal`, `bmr`, `steps_goal`, `hydration_goal`
- **Clear relationships**: Journal belongs_to Patient, Meals/Exercises belong_to Journal
- **Status workflow**: pending_llm → pending_patient → confirmed for meals and exercises
- **Daily closure**: With metrics collection and LLM scoring
- **Data isolation**: Via immutable `patient.professional_id`
- **Timezone & language**: Handled at application level using `user.timezone` and `user.language`
- **Validations**: Comprehensive value range validations
- **Indexes**: Optimized for common query patterns
- **LLM integration**: Interaction-based architecture using ActiveInteraction and ruby_llm gem
- **Implementation plan**: 5-phase development plan with separate PRs for each phase

All decisions from the PRD review have been incorporated into this ERD.
