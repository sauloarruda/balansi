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
- Final “close day” persistence and business scoring completion logic in current initial version (current close action is mock).
- LLM response caching (caching strategy deferred to future versions).

---

## 3. Users & Access Rules

### 3.1 Patient (End User)
- Can access own journal dates (`/journals/:date` and `/journals/today`).
- Can create, edit, confirm, reprocess, and delete own meals/exercises.
- Wants: simple daily logging, clear feedback, low friction.
- Needs: simple forms, understandable comments, trust that the system "gets" what they ate and did.

### 3.2 Professional (Nutritionist)
- Accesses journal through patient scope route (`/professional/patients/:patient_id/journal`).
- Uses the same journal view rendering, with professional date navigation URL template.
- Read-only view.
- Data isolation: Access to records is scoped by `patient.professional_id` (immutable) and `journals.patient_id`. Access to records from other patients must return not found / not leak data.

---

## 4. Date and Navigation Rules

- `GET /journals` redirects to `/journals/:today_in_user_timezone`.
- `GET /journals/today` renders today’s journal in place (no redirect to dated URL).
- `GET /journals/:date`:
  - Invalid date falls back to current date.
  - Future date redirects to `/journals/today`.
  - If no journal exists for the date, response still renders with an unsaved journal payload and empty entries.
- Date navigator uses URL template:
  - Patient view: `/journals/__DATE__`
  - Professional view: `/professional/patients/:patient_id/journal?date=__DATE__`
- Timezone-aware: calculations use user's stored timezone from `users.timezone`.
- Language-aware: UI and LLM use user's stored language from `users.language`.

---

## 5. Entity Rules

### 5.1 Journal Entity

- One journal per patient per date (unique constraint by `patient_id + date`).
- Created automatically for the date if missing when logging a meal or exercise.
- Status helpers:
  - `open?` when `closed_at` is nil.
  - `closed?` when `closed_at` is present.
- Editability window (`editable?`): only closed journals and only up to 2 days after journal date. After that period, closed days become read-only.
- Pending detection:
  - Journal pending if any meal or exercise in `pending_llm` or `pending_patient`.
  - Pending count = pending meals + pending exercises.

### 5.2 Meal Logging Rules

#### Validation
- Required: `meal_type`, `description`.
- `meal_type` in: `breakfast`, `lunch`, `snack`, `dinner`.
- `description` max: 140 chars.
- Macro/calorie fields numeric ranges:
  - `proteins`, `carbs`, `fats`: `0..9999` (when present)
  - `calories`: `1..49999` (when present)
  - `gram_weight`: `1..99999` (when present)
- `feeling` allowed values: positive (`1`) or negative (`0`).

#### Lifecycle
- Initial create: Starts in `pending_llm`.
- AI success: Updated with parsed nutrition, comment (`ai_comment`), and feeling. Status moves to `pending_patient`.
- Patient confirmation: Update with `confirm` param sets status to `confirmed`. Only Confirmed meals are counted in daily totals.
- Reprocess: Allowed from edit/update path with `reprocess` param. Status goes back to `pending_llm`. AI reruns. If AI fails, status is restored.
- Edit/Delete: Supported for confirmed meals. Editing does not revert status to Pending.

### 5.3 Exercise Logging Rules

#### Validation
- Required: `description`.
- `description` max: 140 chars.
- Numeric ranges:
  - `duration`: `1..1439` minutes (max 24 hours, when present)
  - `calories`: `0..9999` (when present)
  - `neat`: `0..4999` (when present)
  - `structured_description`: max 255 chars (when present)

#### Lifecycle
- Mirrors meal lifecycle (`pending_llm` -> `pending_patient` -> `confirmed`).
- AI success sets duration, calories, NEAT, structured description.
- Confirmed exercises are included in daily energy expenditure.

---

## 6. Daily Summary and Calculations

- Confirmed-only aggregation:
  - `calories_consumed` = sum of confirmed meal calories.
  - `exercise_calories_burned` = sum of confirmed exercise calories.
- Burned calories:
  - `calculate_calories_burned = patient.bmr + exercise_calories_burned`.
  - If BMR missing, calculated burned is `0`.
- Effective values shown in UI:
  - `effective_calories_consumed`: stored snapshot if present, else calculated.
  - `effective_calories_burned`: stored snapshot if present, else calculated.
  - `effective_balance = effective_calories_consumed - effective_calories_burned`.

### 6.1 Daily Journal Caloric Balance Card

Defines the business rules for caloric balance status messaging and color coding in the Daily Journal balance card.

**Calculation Inputs:**
- `consumed_calories`: total calories consumed
- `burned_calories`: total calories burned (`BMR + exercise_calories`)
- `daily_calorie_goal`: patient daily calorie goal

**Derived Values:**
- `balance = consumed_calories - burned_calories`
- `goal_lower_bound = daily_calorie_goal * 0.90`
- `goal_upper_bound = daily_calorie_goal * 1.10`
- `burned_lower_bound = burned_calories * 0.85`
- `burned_upper_bound = burned_calories * 1.15`
- `goal_aligned = consumed_calories in [goal_lower_bound, goal_upper_bound]`

**Status Rules & Precedence:**
1. **Weight Gain (Red)**: `consumed_calories >= burned_upper_bound`
   - Intent: user is above expenditure range.
2. **Below Goal (Orange)**: `consumed_calories < goal_lower_bound`
   - Intent: intake is too low for the plan.
3. **Maintenance (Blue)**: `goal_aligned` is true AND `consumed_calories in [burned_lower_bound, burned_upper_bound]`
   - Intent: user is in maintenance range.
4. **Weight Loss (Green)**: `goal_aligned` is true AND `consumed_calories < burned_lower_bound`
   - Intent: user is in a healthy weight-loss range.
5. **Fallback Behavior**:
   - maintenance if `consumed_calories in [burned_lower_bound, burned_upper_bound]`
   - weight loss if `consumed_calories < burned_lower_bound`
   - weight gain otherwise

### 6.2 Macro Goal Indicators

- Macro percentages use patient goals when goal > 0:
  - `macro_goal_percentage = (current / goal * 100).round`
- Excess ring and tooltip logic:
  - If percentage > 100, show red excess ring and `+Xg excess` text.
  - Excess percentage displayed is capped at +100 for ring visualization.
- Tooltip format:
  - With goal: `current/goal + %`
  - Without goal: only current grams.

---

## 7. UX Rules & User Flows

### 7.1 Flow: Log a Meal
1. User opens Daily Journal for today, taps "Add Meal".
2. Selects meal type, types description (max 140 chars), submits.
3. System calls LLM (shows loading). Meal is `pending_llm`.
4. If LLM succeeds: shows review screen (macros, calories, weight, comment, feeling). Meal is `pending_patient`.
5. User can Accept (Confirmed), Edit values, or Edit description & Reprocess (`pending_llm`).
6. On Confirm, daily totals and progress bar update in real-time.

### 7.2 Flow: Log an Exercise
1. User taps "Add Exercise", types description, submits.
2. System calls LLM. Exercise is `pending_llm`.
3. If LLM succeeds: shows review screen (duration, calories, NEAT, structured_description). Exercise is `pending_patient`.
4. User confirms or reprocesses. Confirmed exercise updates energy expenditure.

### 7.3 Flow: Close Day
1. User opens Daily Journal. If pending entries exist, a warning banner is shown: "You have X unconfirmed items. They will be deleted when you close the day."
2. Pending items expose delete actions; `pending_llm` items expose retry/reprocess CTA.
3. User taps "Close Day".
4. Prompted to answer:
   - How are you feeling about the plan? (good/ok/bad)
   - Sleep quality last night (excellent/good/poor)
   - Hydration during the day (excellent/good/poor, compared to daily goal)
   - Daily steps count (numeric, compared to daily goal)
   - Free text note (optional)
5. On confirm:
   - System deletes all Pending entries.
   - Calculates balance with Confirmed entries only.
   - Calls LLM with weekly context to calculate Score (1-5), "what went well", "what to improve".
6. Journal show page hides close-day CTA in daily summary section when day is closed.
7. Current State Note: `GET /journals/:date/close` renders close form. `PATCH /journals/:date/close` currently returns a mock success flash and redirects. No final persistence/business scoring completion in the *current v1 implementation*.

---

## 8. AI Analysis Rules & Prompts

### 8.1 Rate Limiting & Error Handling
- Rate Limit: `50` requests per day, `10` requests per hour per user/entry type.
- Time-bucketed cache keys by user ID.
- Exceeding limit returns invalid and localized `rate_limit_exceeded` error.
- Can be disabled with `DISABLE_LLM_RATE_LIMIT=true`.
- Retry: Up to 3 retries for transient errors with exponential backoff.
- Final failure returns localized unavailable error (`journal.errors.llm_unavailable` / `exercise_llm_unavailable`).
- Unexpected payload failures are logged and sent to Sentry.

### 8.2 AI Payload Shape & Prompts

#### Meal Response Shape
Expected fields: `p` (proteins), `c` (carbs), `f` (fats), `cal` (calories), `gw` (gram weight), `cmt` (comment in user language), `feel` (1 positive, 0 negative). Values cast to integer ranges before persistence.

#### Exercise Response Shape
Expected fields: `d` (duration), `cal` (calories), `n` (NEAT), `sd` (structured description).

#### Daily Scoring Prompt (For future completion)
Context provided:
- Language, Date, Goal, BMR.
- Total calories in, burned, balance.
- feeling, sleep, hydration, steps, note.
- Meals summary (`meal_type|cal|p|c|f|description`)
- Exercises summary (`duration|cal_burned|sd`)
- Weekly context variables (alcohol, red meat, candy, soda, protein goals, exercise frequency, etc.)
- Scoring criteria rules.
Expected fields: `s` (score 1-5), `fp` (feedback_positive), `fi` (feedback_improvement).

---

## 9. Non-Functional Requirements

- **Performance**: LLM responses expected within 3–5 seconds for entries, 5–10 seconds for daily scoring.
- **Data Consistency**: Only Confirmed entries used in totals. Pending entries are excluded.
- **Privacy & Isolation**: Enforced via `patient.professional_id`.
- **Validation**: Strict model-level value ranges for calories, macros, durations.
- **Language**: All prompts and responses use `users.language`. Time calculations use `users.timezone`.
