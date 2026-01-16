# Product Requirements Document — Journal (Balansi)

## 1. Summary

The **Journal** module is the core daily tracking experience of Balansi.
It allows patients to log meals, exercises and progress metrics, and receive AI-assisted feedback based on nutritionist-defined rules and materials.

**Focus (v1)**: The Journal module in v1 focuses specifically on weight loss goals, with quality of life guardrails to ensure healthy and sustainable progress.

The User Journal must be:
- fast to use,
- easy to understand,
- and reliable for daily feedback.

---

## 2. Goals & Non-Goals

### 2.1 Goals

- Allow patients to quickly log:
  - meals (with free text descriptions)
  - exercises (with free text descriptions)
- Use LLM (OpenAI) to:
  - estimate macros, calories and daily evaluation
  - estimate calories, NEAT and structured exercise descriptions
  - calculate daily qualitative feedback and score (1–5)
  - generate daily summary and guidance
- Enforce nutritionist-driven logic:
  - configurable scoring rules
- Provide a clear **daily** view of progress.

### 2.2 Non-Goals (for v1)

- Real-time device integrations (smartwatches, health APIs).
- Processing images related to meals or exercise.
- Multi-nutritionist workflows per patient.
- Advanced analytics / cohort dashboards for professionals.
- In-depth habit coaching or chat-style conversations.
- LLM response caching (caching strategy deferred to future versions).

---

## 3. Users & Personas

### 3.1 Patient (End User)

- Wants: simple daily logging, clear feedback, low friction.
- Needs:
  - simple forms
  - understandable comments (no medical jargon)
  - trust that the system "gets" what they ate and did

### 3.2 Nutritionist (Professional)

- Wants: structured, reliable data and AI that respects their protocol.
- Needs:
  - access their patients' journals

---

## 4. Scope

### 4.1 In Scope

- Meal logging (with AI + manual override + review flow).
- Exercise logging (with AI + manual override + review flow).
- Daily closure:
  - total calories consumed
  - total calories spent (basal + exercises)
  - daily caloric balance
  - daily score based on nutritionist rules
  - daily comments (what was good / what to improve)
- Multi-language support in UI (en and pt)
- Timezone-aware date calculations (uses user's stored timezone from `users.timezone`)
- Language-aware LLM interactions (uses user's stored language from `users.language` for prompts and responses)

### 4.2 Out of Scope (v1)

- Full admin tooling for clinic-level management.
- Notifications / reminders.
- Offline mode.
- Duplicate meal detection or merging.

---

## 5. Functional Requirements

### 5.1 Meal Logging

**FR-ML-01**: The user can select:
- date (default: today)
- meal type: breakfast, lunch, snack, dinner

**FR-ML-02**: The user can input a free-text description of what they ate (maximum 140 characters).

**FR-ML-03**: The LLM returns:
- proteins (g)
- carbs (g)
- fats (g)
- calories (kcal)
- estimated total gram weight
- comment about the meal
- feeling (positive or negative)

**FR-ML-04**: The meal is initially saved in **Pending** status and shown in a **review step**.

**FR-ML-05**: In the review step, the user can:
- **Accept as-is** → mark as Confirmed.
- **Adjust specific fields**:
  - calories
  - proteins
  - carbs
  - fats
  - gram weight
- **Reprocess with AI**:
  - edit the description
  - ask AI to recalculate
  - receive a new proposal, still Pending until confirmed.

**FR-ML-06**: Only **Confirmed** meals are counted in daily totals.

**FR-ML-07**: Users can edit or delete **Confirmed** meals. Editing a confirmed meal does not change its status back to Pending (Pending status only denotes items that need AI review).

**FR-ML-08**: Meal types are fixed: `breakfast`, `lunch`, `snack`, `dinner`.

---

### 5.2 Exercise Logging

**FR-EX-01**: The user can input a free-text exercise description (maximum 140 characters).

**FR-EX-02**: The system sends the description to the LLM.

**FR-EX-03**: The LLM returns:
- estimated calories burned
- estimated duration
- NEAT (if applicable)
- structured description (e.g. "5 km moderate run")

**FR-EX-04**: The exercise is initially **Pending** and shown in a review step.

**FR-EX-05**: In the review step, the user can:
- **Accept as-is** → Confirmed.
- **Adjust fields**:
  - duration
  - calories
  - NEAT
  - structured description
- **Reprocess with AI** with a refined description.

**FR-EX-06**: Only **Confirmed** exercises are included in daily energy expenditure.

---

### 5.3 Daily Closure

**FR-DC-01**: The user can tap **"Close Day"** for a given date.

**FR-DC-02**: The system:
- asks user to confirm all **Pending** entries and aggregates all **Confirmed** meals and exercises
- computes:
  - total calories consumed
  - total calories burned (basal + exercises)
  - daily caloric balance (consumed – burned)

**FR-DC-03**: The system sends daily context to the LLM:
- meals (+ macros and calories)
- exercises (+ calories)
- nutritionist scoring rules
- weekly context

**FR-DC-04**: The LLM returns:
- daily score (1–5) according to nutritionist rules
- short "what went well" commentary
- short "what to improve" commentary

**FR-DC-05**: If there are **Pending** entries, the system should:
- show an alert warning the user about unconfirmed items
- upon closure, automatically delete all Pending entries for that day

**FR-DC-06**: Users can only close one day at a time. The Daily Journal screen always relates to a single day.

**FR-DC-07**: Users can edit a closed day up to 2 days after the journal date. After that period, closed days become read-only.

**FR-DC-08**: Before closing the day, the user must answer:
- How are you feeling about the plan: 3 options - good, ok, bad
- Sleep quality last night: 3 options - excellent, good, poor
- Hydration during the day (based on patient profile goal): 3 options - excellent, good, poor
- Daily steps count (numeric, compared against patient profile goal)
- Free text note (optional, user can write anything they want)

**FR-DC-09**: Weekly context variables are passed to the LLM scoring prompt:
- Current day of week (1-7, where Sunday = 1, Monday = 2, ..., Saturday = 7)
- Number of days with journal entries so far this week (up to current day)
- Days with alcohol consumption so far this week (out of {day_of_week} days)
- Days with red meat consumption so far this week (out of {day_of_week} days)
- Days with candy consumption so far this week (out of {day_of_week} days)
- Days with soda consumption so far this week (out of {day_of_week} days)
- Days meeting daily protein goal so far this week (out of {day_of_week} days)
- Days with exercise so far this week (out of {day_of_week} days)
- Days meeting daily steps goal so far this week (out of {day_of_week} days)
- Days with score 3 or less so far this week (out of {day_of_week} days)
- Days with processed foods consumption so far this week (out of {day_of_week} days)
- Days with quality sleep so far this week (out of {day_of_week} days)
- Days with adequate hydration so far this week (out of {day_of_week} days)
- Days feeling bad so far this week (out of {day_of_week} days)

---

## 6. User Flows

### 6.1 Flow: Log a Meal

1. User opens "Daily Journal" for today.
2. Taps "Add Meal".
3. Selects meal type (default based on time).
4. Types description in free text.
5. Submits.
6. System calls LLM (shows loading indicator).
7. If LLM succeeds, shows a **review screen**:
   - macros
   - calories
   - gram weight
   - comment
   - feeling (positive or negative)
8. If LLM fails, shows error message with "Retry" button.
9. User:
   - accepts, or
   - edits fields and saves, or
   - edits description and reprocesses with AI.
10. On accept or save:
   - meal becomes **Confirmed**
   - daily totals and progress bar update in real-time.

### 6.2 Flow: Log an Exercise

1. User opens "Daily Journal".
2. Taps "Add Exercise".
3. Types description.
4. System calls LLM (shows loading indicator).
5. If LLM succeeds, shows:
   - duration
   - calories
   - NEAT
   - structured description
6. If LLM fails, shows error message with "Retry" button.
7. User:
   - accepts, or
   - adjusts fields, or
   - reprocesses with new description.
8. On confirm, exercise is saved as **Confirmed** and included in energy expenditure. Daily totals and progress bar update in real-time.

### 6.3 Flow: Close Day

1. User opens Daily Journal for a specific date.
2. Sees:
   - list of meals and exercises (with status)
   - current totals
   - progress bar toward daily calorie goal
3. If there are Pending entries:
   - alert: "You have X unconfirmed items. They will be deleted when you close the day."
4. User taps "Close Day".
5. System prompts user to answer:
   - How are you feeling about the plan? (good/ok/bad)
   - Sleep quality last night (excellent/good/poor)
   - Hydration during the day (excellent/good/poor, compared to daily goal)
   - Daily steps count (numeric, compared to daily goal)
   - Free text note (optional)
6. User answers and confirms.
7. System:
   - deletes all Pending entries for that day
   - calculates balance and calls LLM with Confirmed entries only
   - includes weekly context variables in the prompt
8. User sees:
   - daily balance
   - score
   - "what went well"
   - "what to improve"
9. Day is marked as closed (can be edited up to 2 days after the journal date).

---

## 7. Screens (High-Level)

### 7.1 Daily Journal Screen

- **Date Navigator**: Component displaying "< [Date] >" format (e.g., "< Today (Jan, 14) >")
  - Left arrow navigates to previous day
  - Right arrow navigates to next day
  - Clicking on the date opens a calendar picker
  - Journal records are created automatically when the first meal or exercise is logged for that date
- **Summary**:
  - total calories in (from Confirmed meals only)
  - total calories out (basal + Confirmed exercises)
  - balance (consumed – burned)
  - progress bar showing daily progress toward patient's daily calorie goal
  - last score (if day is closed)
- **Sections**:
  - Meals list (with status badges: Pending / Confirmed)
  - Exercises list (with status badges)
- **Actions**:
  - Add Meal
  - Add Exercise
  - Close Day (if day is not closed, or if within 2 days of journal date)

### 7.2 Meal Entry / Review Screen

- Fields:
  - Date (default today)
  - Meal type
  - Free text description (editable)
- After AI:
  - Macros, calories, gram weight, comment
  - Feeling (positive or negative indicator)
  - Status banner: "AI suggestion"
- Actions:
  - Confirm meal
  - Edit values
  - Edit description & Reprocess
  
### 7.3 Exercise Entry / Review Screen

- Fields:
  - Date
  - Free text description
- After AI:
  - duration, calories, NEAT, structured description
- Actions:
  - Confirm
  - Edit values
  - Edit description & Reprocess

---

## 8. Non-Functional Requirements

### 8.1 Performance

- Fast interactions (AI calls aside).
- **LLM Response Time**: Users should receive LLM responses within 3–5 seconds for meal/exercise analysis and 5–10 seconds for daily scoring. Loading indicators should be shown during processing.

### 8.2 Error Handling

- **LLM Failures**: When LLM calls fail or return invalid data:
  - Show clear, user-friendly error messages in the user's language
  - Display a "Retry" button to attempt the LLM call again
  - Log errors with context for debugging

### 8.3 Rate Limiting & Cost Control

- **API Rate Limits**: Implement rate limiting to prevent excessive API usage:
  - Suggested: Maximum 50 LLM calls per user per day
  - Suggested: Maximum 10 LLM calls per user per hour
- **Retry Strategy**: On transient failures (network issues, rate limits):
  - Automatic retry with exponential backoff (max 3 retries)

### 8.4 Data Consistency

- Only Confirmed entries are used in daily totals and summaries.
- Pending entries are excluded from calculations until confirmed.

### 8.5 Privacy & Data Isolation

- Patient data must be isolated per nutritionist / clinic.
- Data isolation enforced via `patient.professional_id` (immutable once set).
- Nutritionists can view the same journal view as patients (read-only access).

### 8.6 Validation

- Model-level validations required for:
  - Meal macros (proteins, carbs, fats) and calories (reasonable ranges)
  - Exercise duration, calories, and NEAT
  - Value ranges to prevent unrealistic entries (e.g., calories > 0 and < 50,000)

---

## 9. LLM Integration & Prompts

### 9.1 Model Selection

- **Initial Model**: OpenAI GPT-5.2
- **Future Consideration**: Test and evaluate cost/performance of other models (GPT-3.5-turbo, GPT-4, etc.)

### 9.2 Language Handling

- All prompts and responses must be in the user's language (`users.language`).

### 9.3 Meal Analysis Prompt

**Purpose**: Extract macros, calories, and generate meal comment.

**Context to Include**:
- User's language (for prompt and expected response language)
- Meal description (free text)
- Meal type (breakfast, lunch, snack, dinner)

**Expected JSON Response Format** (abbreviated to minimize tokens and storage):
```json
{
  "p": 25.5,
  "c": 45.0,
  "f": 15.2,
  "cal": 380,
  "gw": 250,
  "cmt": "Balanced meal with good protein source",
  "feel": 1
}
```

**Field Mappings:**
- `p`: proteins (g)
- `c`: carbs (g)
- `f`: fats (g)
- `cal`: calories (kcal)
- `gw`: gram_weight (g)
- `cmt`: comment (text)
- `feel`: feeling (1 = positive, 0 = negative)

**Proposed Prompt Template**:
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

### 9.4 Exercise Analysis Prompt

**Purpose**: Extract exercise metrics and structured description.

**Context to Include**:
- User's language
- Exercise description (free text)

**Expected JSON Response Format** (abbreviated to minimize tokens and storage):
```json
{
  "d": 30,
  "cal": 250,
  "n": 50,
  "sd": "5 km moderate run"
}
```

**Field Mappings:**
- `d`: duration (minutes)
- `cal`: calories (kcal)
- `n`: neat (kcal)
- `sd`: structured_description (text)

**Proposed Prompt Template**:
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

### 9.5 Daily Scoring Prompt

**Purpose**: Calculate daily score (1–5) and generate feedback with focus on weight loss while maintaining quality of life.

**Context to Include**:
- User's language
- All confirmed meals for the day (with macros, calories, meal type, and description)
- All confirmed exercises for the day (with duration, calories, and intensity)
- Patient's daily calorie goal
- Patient's basal metabolic rate (BMR)
- Patient's steps goal
- Total calories consumed (from confirmed meals)
- Total calories burned (BMR + exercises)
- Daily metrics (sleep quality, hydration, steps, feeling, note)
- Weekly context variables (day of week, days with entries, alcohol, red meat, candy, soda, protein goals, exercise frequency, steps goals, low scores, processed foods, quality sleep, adequate hydration, feeling bad)
- Scoring criteria (configurable rules provided as variable)

**Meals Summary Format**:
Each meal should be formatted as a single line with pipe-separated values:
```
{meal_type}|{cal}|{p}|{c}|{f}|{description}
```

Example:
```
breakfast|450|30|55|12|Oatmeal with fruits and nuts
lunch|680|45|70|18|Grilled chicken with rice and vegetables
snack|150|8|20|5|Cookies
dinner|520|35|45|15|Fish with sweet potato and salad
```

**Exercises Summary Format**:
Each exercise should be formatted as a single line with pipe-separated values:
```
{duration_min}|{cal_burned}|{sd}
```

Example:
```
30|250|5 km moderate walk
45|380|Light strength training
20|150|Yoga session
```

**Scoring Criteria Variable** (`{scoring_criteria}`):

The scoring criteria is a configurable variable that contains detailed instructions. Each nutritionist (professional) configures scoring criteria individually for each patient based on their specific needs, goals, and health conditions. Below is the template structure that should be used when configuring scoring criteria per patient, with examples for different patient profiles.

**Scoring Criteria Template Structure**:

The scoring criteria should focus on daily metrics that can be evaluated from the current day's data. Weekly metrics are provided as context but should be used as supporting information, not primary scoring factors.

```
Balance caloric deficit with nutritional adequacy, exercise appropriateness, and sustainable habits.

Scoring criteria:
SCORE 5
- Caloric balance: Within -200 and +100 kcal of daily goal (considering BMR + exercise)
- Protein: Within {min_protein}g - {max_protein}g range
- 2 meals with fruit
- 2 meals with vegetable servings
- Exercise: Present today with appropriate intensity for patient profile
- Meal quality: All meals nutritionally balanced (evaluate from descriptions and macros)
- Sleep: Excellent quality (from user input)
- Hydration: Excellent (from user input, meeting daily goal)
- Steps: Meeting daily goal (from user input)
- No candy

SCORE 4
- Caloric balance: Within -300 and +150 of goal 
- 1 meals with fruit
- 2 meals with vegetable servings
- Exercise present but may be slightly below target intensity/duration
- Occasional processed foods detectable
- Sleep: Good quality
- Hydration: Good (close to daily goal)
- Steps: Close to daily goal
- No candy

SCORE 3
- Caloric balance: Within -500 and +300 kcal of goal
- 1 meals with fruit
- 1 meals with vegetable servings
- Exercise missing or intensity/duration inappropriate for patient profile
- Multiple processed food meals detectable
- Sleep: Poor quality
- Hydration: Poor (significantly below daily goal)
- Steps: Below daily goal
- Little candy allowed

SCORE 2:
- Caloric balance: >500 kcal deficit OR >300 kcal surplus
- Severe macro imbalances (e.g., protein too low, excessive carbs/fats)
- <60% of fruit/vegetable servings
- No exercise OR excessive exercise intensity (especially for obese patients)
- Excessive processed foods
- Sleep: Poor quality
- Hydration: Poor (well below daily goal)
- Steps: Well below daily goal

SCORE 1:
- Severe caloric restriction (<1200 kcal for women, <1500 for men) OR large surplus (>800 kcal)
- Critical macro deficiencies
- Minimal to no fruits/vegetables
- No exercise OR dangerous exercise intensity
- Sleep: Poor quality
- Hydration: Very poor (minimal water intake)
- Steps: Minimal or no steps

EXERCISE INTENSITY GUARDRAILS:
- Obese patients (BMI >30): Prefer light-moderate intensity. High intensity exercises should reduce score. Start gradual.
- Normal/overweight: Moderate to high intensity acceptable based on fitness level.
- If exercise intensity too high for patient profile → reduce score by 1 point, warn in feedback.

QUALITY OF LIFE PRIORITIES:
1. Prevent extreme caloric restriction that may cause muscle loss, fatigue, or metabolic issues
2. Ensure adequate protein to preserve muscle during weight loss
3. Maintain variety and micronutrient intake (fruits/vegetables)
4. Promote sustainable exercise habits appropriate to patient's condition
5. Avoid over-restriction that leads to binge eating or unsustainable patterns
6. Encourage quality sleep and adequate hydration
7. Promote daily movement (steps) appropriate to patient's condition

Note: Weekly context variables (alcohol, red meat, processed foods, etc.) should be considered as supporting information but not primary scoring factors. They help inform feedback but daily performance is evaluated primarily from today's data.
```

**Expected JSON Response Format** (abbreviated to minimize tokens and storage):
```json
{
  "s": 4,
  "fp": "Good protein intake and consistent exercise routine",
  "fi": "Consider reducing evening snacks to improve caloric balance"
}
```

**Field Mappings:**
- `s`: score (1-5)
- `fp`: feedback_positive (text)
- `fi`: feedback_improvement (text)

**Proposed Prompt Template**:
```
Evaluate daily journal and calculate score (1-5).

Lang: {user_language}
Date: {date}

Patient: goal={daily_calorie_goal}kcal, BMR={bmr}kcal
Daily: consumed={total_calories_in}kcal, burned={total_calories_out}kcal (BMR {bmr}+ex {exercise_calories}), balance={balance}kcal
Metrics: feeling={feeling_today}, sleep={sleep_quality}, hydration={hydration_quality} (goal {hydration_goal}ml), steps={steps_count} (goal {steps_goal})
Note: {daily_note}

Meals ({meal_count}):
{meals_summary}

Exercises ({exercise_count}):
{exercises_summary}

Week (day {day_of_week} of 7, {days_with_entries} days with entries):
- Alcohol: {days_with_alcohol}/{day_of_week}, Red meat: {days_with_red_meat}/{day_of_week}, Candy: {days_with_candy}/{day_of_week}, Soda: {days_with_soda}/{day_of_week}
- Protein goal: {days_meeting_protein}/{day_of_week}, Exercise: {days_with_exercise}/{day_of_week}, Steps goal: {days_meeting_steps}/{day_of_week}
- Score ≤3: {days_score_low}/{day_of_week}, Processed: {days_with_processed}/{day_of_week}
- Quality sleep: {days_quality_sleep}/{day_of_week}, Hydration: {days_adequate_hydration}/{day_of_week}, Feeling bad: {days_feeling_bad}/{day_of_week}

Criteria:
{scoring_criteria}

Calculate score. Consider balance, macros, meal quality, exercise appropriateness, quality of life.

Return JSON:
{
  "s": <1-5>,
  "fp": "<what went well, 2-3 sentences, {user_language}>",
  "fi": "<what to improve, 2-3 sentences, {user_language}>"
}
```

**Note**: 
- Scoring criteria will be configurable per nutritionist in future versions. 
- For v1, default scoring criteria templates will be provided via seed data and detailed in the ERD.
- The `{scoring_criteria}` variable should be populated with the appropriate template based on patient profile (obesity level, gender, weight loss goal).
