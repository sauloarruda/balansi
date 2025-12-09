# Technical Specification & ERD — User Journal (Balansi)

## 1. Architecture Overview

- Client: Web/mobile.
- Backend: API service (e.g., Elixir) responsible for:
  - authentication
  - database persistence
  - OpenAI orchestration
  - daily and weekly calculations
- LLM Provider: OpenAI GPT (4.1 or newer)

All LLM calls must go through a dedicated service (LLMService) with strict input/output contracts.

---

## 2. Data Model / ERD

### 2.1 Entities

User
- id (PK)
- nutritionist_id (FK → Nutritionist)
- email
- name
- created_at
- updated_at

Nutritionist
- id (PK)
- name
- email
- created_at
- updated_at

UserProfile
- id (PK)
- user_id (FK → User)
- height_cm
- birth_year
- gender (male, female)
- goal (fat_loss, muscle_gain, disease_treatment)
- created_at
- updated_at

MealEntry
- id (PK)
- user_id (FK → User)
- date
- meal_type (breakfast, lunch, snack, dinner)
- original_description
- final_description
- protein_g
- carbs_g
- fat_g
- calories_kcal
- weight_g
- comment (nullable)
- status (pending, confirmed)
- has_manual_override (boolean)
- overridden_fields (jsonb)
- llm_raw_response (jsonb, nullable)
- source_recipe_id (FK → Recipe, nullable)
- created_at
- updated_at

ExerciseEntry
- id (PK)
- user_id (FK → User)
- date
- original_description
- final_description
- duration_minutes
- calories_kcal
- neat (nullable)
- structured_description
- status (pending, confirmed)
- has_manual_override (boolean)
- overridden_fields (jsonb)
- llm_raw_response (jsonb, nullable)
- created_at
- updated_at

DailySummary
- id (PK)
- user_id (FK → User)
- date
- total_calories_in
- total_calories_out
- basal_calories
- exercise_calories
- balance_calories
- score (1–5)
- comment_positive
- comment_improve
- llm_raw_response (jsonb)
- created_at
- updated_at

WeeklySummary
- id (PK)
- user_id (FK → User)
- week_start_date
- week_end_date
- days_data (jsonb, e.g., list of { date, balance, score })
- llm_raw_response (jsonb)
- comment_week
- estimated_weight_change_kg (nullable)
- created_at
- updated_at

Recipe
- id (PK)
- owner_type (user, nutritionist)
- owner_id
- title
- description
- default_protein_g (nullable)
- default_carbs_g (nullable)
- default_fat_g (nullable)
- default_calories_kcal (nullable)
- default_weight_g (nullable)
- created_at
- updated_at

TrackingData
- id (PK)
- user_id
- date
- weight_kg
- body_fat_pct (nullable)
- muscle_pct (nullable)
- water_pct (nullable)
- abdominal_circumference_cm (nullable)
- created_at
- updated_at

NutritionistConfig
- id (PK)
- nutritionist_id
- scoring_rules (jsonb)
  Example:
    {
      "protein": { "min": 90, "max": 150 },
      "deficit": { "preferred_max_surplus": 200 },
      "alcohol": { "max_occurrences_per_week": 2 },
      "training": { "min_sessions_per_week": 3 }
    }
- created_at
- updated_at

Material
- id (PK)
- nutritionist_id
- type (pdf, video, note)
- title
- url
- content
- created_at
- updated_at

---

## 3. API Design (High-Level)

### 3.1 Meals

POST /users/{id}/meals
- Creates a MealEntry with status = pending
- Calls LLM to estimate macros/calories/comment
- Stores the raw LLM response
- Returns the proposed values for user review

PATCH /meals/{meal_id}
- Allows updating:
  - final_description
  - protein_g, carbs_g, fat_g
  - calories_kcal, weight_g
  - comment
- Marks has_manual_override = true if numeric fields change
- Updates overridden_fields

POST /meals/{meal_id}/confirm
- Sets status = confirmed

POST /meals/{meal_id}/reprocess
- Accepts a new/updated description
- Calls LLM again
- Updates macros/calories
- Keeps status = pending

GET /users/{id}/meals?date=YYYY-MM-DD

---

### 3.2 Exercises

POST /users/{id}/exercises
- Creates ExerciseEntry with status = pending
- Calls LLM for duration/calories/NEAT
- Returns proposal

PATCH /exercises/{exercise_id}
- Allows overriding:
  - duration_minutes
  - calories_kcal
  - neat
  - structured_description
- Marks override flags

POST /exercises/{exercise_id}/confirm

POST /exercises/{exercise_id}/reprocess

GET /users/{id}/exercises?date=YYYY-MM-DD

---

### 3.3 Daily Summary

POST /users/{id}/days/{date}/close
- Loads all confirmed meals and exercises
- Computes:
  - total_calories_in
  - basal_calories
  - exercise_calories
  - total_calories_out
  - balance_calories
- Calls LLM for:
  - score
  - comment_positive
  - comment_improve
- Saves DailySummary
- Returns summary

GET /users/{id}/days/{date}

---

### 3.4 Weekly Summary

POST /users/{id}/weeks/close?start_date=YYYY-MM-DD
- Aggregates daily summaries
- Loads tracking data
- Calls LLM
- Saves WeeklySummary
- Returns result

GET /users/{id}/weeks?start_date=YYYY-MM-DD

---

### 3.5 Tracking Data

POST /users/{id}/tracking
GET /users/{id}/tracking?from=YYYY-MM-DD&to=YYYY-MM-DD

---

### 3.6 Nutritionist Area

GET /nutritionists/{id}/config
PATCH /nutritionists/{id}/config

POST /nutritionists/{id}/materials
GET /nutritionists/{id}/materials

POST /nutritionists/{id}/recipes
GET /nutritionists/{id}/recipes

---

## 4. LLM Prompt Specifications

### 4.1 Meal Estimation Prompt

Input includes:
- user_profile (age, gender, goal)
- nutritionist_scoring_rules
- nutritionist_recipes (names + rough macros)
- user_recipes
- meal_description

Expected Output (JSON):

    {
      "protein_g": 25,
      "carbs_g": 45,
      "fat_g": 10,
      "calories_kcal": 450,
      "weight_g": 250,
      "comment": "Balanced breakfast with good protein and moderate carbs."
    }

Validation required:
- All fields must exist
- Values must be numeric and reasonable

---

### 4.2 Exercise Estimation Prompt

Input:
- user_profile (age, gender, optional weight)
- exercise_description

Expected Output:

    {
      "duration_minutes": 45,
      "calories_kcal": 380,
      "neat": 100,
      "structured_description": "45 minutes of moderate-intensity running."
    }

---

### 4.3 Daily Closure Prompt

Input:
- user_profile
- nutritionist_scoring_rules
- nutritionist_materials (summarized)
- total_calories_in
- total_calories_out
- balance_calories
- list of meals
- list of exercises

Expected Output:

    {
      "score": 4,
      "comment_positive": "Good protein intake and light caloric deficit.",
      "comment_improve": "Add vegetables at dinner and reduce refined carbs."
    }

---

### 4.4 Weekly Closure Prompt

Input:
- user_profile
- daily_summaries
- tracking_data
- goal

Expected Output:

    {
      "estimated_weight_change_kg": -0.4,
      "comment_week": "Consistent mild deficit with likely small fat loss.",
      "guidance_next_week": "Maintain deficit and prioritize vegetables."
    }

---

## 5. Services & Interfaces

LLMService
- estimateMeal(input)
- estimateExercise(input)
- closeDay(input)
- closeWeek(input)

MealService
- createMeal
- reprocessMeal
- updateMeal
- confirmMeal
- getMealsForDay

ExerciseService
- createExercise
- reprocessExercise
- updateExercise
- confirmExercise
- getExercisesForDay

DailySummaryService
- closeDay
- getDaySummary

WeeklySummaryService
- closeWeek
- getWeekSummary

---

## 6. Task Breakdown & Estimates

Backend
- Entities & migrations: 1 day
- CRUD (profile, tracking, recipes, config): 1–2 days
- LLMService implementation: 1 day
- Meal AI flow: 2 days
- Exercise AI flow: 1.5–2 days
- Daily summary flow: 1–1.5 days
- Weekly summary flow: 1–1.5 days
- Nutritionist config/materials: 2–3 days

Frontend
- Daily Journal screen: 1–1.5 days
- Meal entry + review: 1–1.5 days
- Exercise entry + review: 1 day
- Tracking screen: 1 day
- Daily summary section: 0.5–1 day
- Weekly summary + charts: 1.5–2 days
- Nutritionist screens: 3 days

Prompt Engineering
- draft prompts: 1 day
- synthetic test cases: 1 day
- refine prompts for stability: 1 day

---

## 7. Risks & Considerations

- LLM may return invalid or partial JSON → must sanitize and validate fields
- Large nutritionist materials may require summarization
- User may log vague meal/exercise descriptions
- Overrides must be clearly represented to avoid bad data
