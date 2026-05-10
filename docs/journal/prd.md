# Daily Journal PRD

## Objective

Define the product and business rules for the Daily Journal flow, including navigation, entry lifecycle, AI analysis, calculations, and UI feedback.

## Scope

- Patient journal page by date (`/journals/:date`) and today shortcut (`/journals/today`).
- Meal and exercise logging with AI pre-analysis.
- Manual confirmation/editing and reprocessing flow.
- Daily summary metrics, macro goal indicators, and caloric balance visual status.
- Professional read-only view of patient journal (`/professional/patients/:patient_id/journal`).

## Out of Scope

- Final “close day” persistence and scoring logic (current close action is mock).

## Actors and Access Rules

- Patient:
  - Can access own journal dates.
  - Can create, edit, confirm, reprocess, and delete own meals/exercises.
- Professional:
  - Accesses journal through patient scope route.
  - Uses the same journal view rendering, with professional date navigation URL template.
- Data isolation:
  - Meal/exercise lookup is scoped by `current_patient` through `journals.patient_id`.
  - Access to records from other patients must return not found / not leak data.

## Date and Navigation Rules

- `GET /journals` redirects to `/journals/:today_in_user_timezone`.
- `GET /journals/today` renders today’s journal in place (no redirect to dated URL).
- `GET /journals/:date`:
  - Invalid date falls back to current date.
  - Future date redirects to `/journals/today`.
  - If no journal exists for the date, response still renders with an unsaved journal payload and empty entries.
- Date navigator uses URL template:
  - Patient view: `/journals/__DATE__`
  - Professional view: `/professional/patients/:patient_id/journal?date=__DATE__`

## Journal Entity Rules

- One journal per patient per date (unique constraint by `patient_id + date`).
- Status helpers:
  - `open?` when `closed_at` is nil.
  - `closed?` when `closed_at` is present.
- Editability window (`editable?`): only closed journals and only up to 2 days after journal date.
- Pending detection:
  - Journal pending if any meal or exercise in `pending_llm` or `pending_patient`.
  - Pending count = pending meals + pending exercises.

## Meal Rules

### Validation

- Required: `meal_type`, `description`.
- `meal_type` in: `breakfast`, `lunch`, `snack`, `dinner`.
- `description` max: 500 chars.
- Macro/calorie fields numeric ranges:
  - `proteins`, `carbs`, `fats`: `0..9999` (when present)
  - `calories`: `1..49999` (when present)
  - `gram_weight`: `1..99999` (when present)
- `feeling` allowed values: positive (`1`) or negative (`0`).

### Lifecycle

- Initial create:
  - Journal is created for date if missing.
  - Meal starts in `pending_llm`.
- AI success:
  - Meal updated with parsed nutrition + comment + feeling.
  - Status moves to `pending_patient`.
- Patient confirmation:
  - Update with `confirm` param sets status to `confirmed`.
- Reprocess:
  - Allowed from edit/update path with `reprocess` param.
  - Status goes to `pending_llm`, AI reruns.
  - If reprocess AI fails, status is restored to previous status.
- Deletion:
  - Meal can be deleted from journal flow.

## Exercise Rules

### Validation

- Required: `description`.
- `description` max: 500 chars.
- Numeric ranges:
  - `duration`: `1..1439` minutes (when present)
  - `calories`: `0..9999` (when present)
  - `neat`: `0..4999` (when present)
  - `structured_description`: max 255 chars (when present)

### Lifecycle

- Mirrors meal lifecycle:
  - Create in `pending_llm`.
  - AI success sets structured fields and status `pending_patient`.
  - Confirm moves to `confirmed`.
  - Reprocess restores previous status on AI failure.
  - Delete supported.

## AI Analysis Rules

### Rate Limiting

- Applied per user and per entry type interaction.
- Limits:
  - `50` requests per day
  - `10` requests per hour
- Keys are time-bucketed cache keys by user id.
- If limit exceeded:
  - interaction returns invalid
  - localized `rate_limit_exceeded` error is returned.
- Can be disabled with `DISABLE_LLM_RATE_LIMIT=true`.

### Retry and Failure Handling

- Up to 3 retries for transient errors with exponential backoff.
- Final failure returns localized unavailable error:
  - Meal: `journal.errors.llm_unavailable`
  - Exercise: `journal.errors.exercise_llm_unavailable`
- Meal unexpected/invalid payload failures are logged and sent to Sentry.

### Required AI Payload Shape

- Meal response must include: `p`, `c`, `f`, `cal`, `gw`, `cmt`, `feel`.
- Exercise response must include: `d`, `cal`, `n`, `sd`.
- Values are cast and validated against model-compatible ranges before persistence.

## Daily Summary and Calculations

- Confirmed-only aggregation:
  - `calories_consumed` = sum of confirmed meal calories.
  - `exercise_calories_burned` = sum of confirmed exercise calories.
- Burned calories:
  - `calculate_calories_burned = patient.bmr + exercise_calories_burned`.
  - If BMR missing, calculated burned is `0`.
- Effective values shown in UI:
  - `effective_calories_consumed`: stored snapshot if present, else calculated.
  - `effective_calories_burned`: stored snapshot if present, else calculated.
  - `effective_balance = effective_consumed - effective_burned`.
- Journal balance status helper:
  - `positive` if `effective_balance > 300`
  - `negative` if `effective_balance < -500`
  - else `balanced`

## Macro Goal Indicators

- Macro percentages use patient goals when goal > 0:
  - `macro_goal_percentage = (current / goal * 100).round`
- Excess ring and tooltip logic:
  - If percentage > 100, show red excess ring and `+Xg excess` text.
  - Excess percentage displayed is capped at +100 for ring visualization.
- Tooltip format:
  - With goal: `current/goal + %`
  - Without goal: only current grams.

## Pending Entry UX Rules

- When journal has pending entries and is open, show warning banner with pending count.
- Pending items expose delete actions.
- `pending_llm` items expose retry/reprocess CTA.
- Journal show page does not render close-day CTA in daily summary section.

## Professional View Rules

- Professional patient journal endpoint renders shared `journals/show` template.
- Breadcrumb and patient context banner are shown when professional context is present.
- Date navigation in professional context must keep professional patient route template.

## Close Day (Current State)

- `GET /journals/:date/close` renders close form and summary preview.
- `PATCH /journals/:date/close` currently returns mock success flash and redirects back to journal date.
- No final persistence/business scoring completion in current implementation.

## Subsection: Daily Journal Caloric Balance Card

## Objective

Define the business rules for caloric balance status messaging and color coding in the Daily Journal balance card.

## Calculation Inputs

- `consumed_calories`: total calories consumed by the patient.
- `burned_calories`: total calories burned (`BMR + exercise_calories`).
- `daily_calorie_goal`: patient daily calorie goal.

## Core Derived Values

- `balance = consumed_calories - burned_calories`
- `goal_lower_bound = daily_calorie_goal * 0.90`
- `goal_upper_bound = daily_calorie_goal * 1.10`
- `burned_lower_bound = burned_calories * 0.85`
- `burned_upper_bound = burned_calories * 1.15`
- `goal_aligned = consumed_calories in [goal_lower_bound, goal_upper_bound]`

## Status Rules

### 1. Weight Gain (Red)

Show **Weight Gain** when consumed calories are at least 15% above total burned:

- `consumed_calories >= burned_upper_bound`

Message intent: user is above expenditure range.
Color: **Red**.

### 2. Below Goal (Orange)

Show **Below Goal** when consumed calories are below 90% of daily goal:

- `consumed_calories < goal_lower_bound`

Message intent: intake is too low for the plan.
Color: **Orange**.

### 3. Maintenance (Blue)

Show **Maintenance** when goal-aligned intake is also inside expenditure maintenance range:

- `goal_aligned` is true
- `consumed_calories in [burned_lower_bound, burned_upper_bound]`

Message intent: user is in maintenance range.
Color: **Blue**.

### 4. Weight Loss (Green)

Show **Weight Loss** when goal-aligned intake is below maintenance expenditure range:

- `goal_aligned` is true
- `consumed_calories < burned_lower_bound`

Message intent: user is in a healthy weight-loss range.
Color: **Green**.

### 5. Fallback Behavior

When intake is not goal-aligned, classify by expenditure range only:

- maintenance if `consumed_calories in [burned_lower_bound, burned_upper_bound]`
- weight loss if `consumed_calories < burned_lower_bound`
- weight gain otherwise

## Rule Precedence

To ensure deterministic behavior, evaluate in this order:

1. Weight Gain (Red)
2. Below Goal (Orange)
3. Maintenance (Blue)
4. Weight Loss (Green)
5. Fallback by expenditure range

## Notes

- This rule fixes cases where a patient is goal-aligned (for example, 1350 kcal on a 1300 kcal goal) and should be classified as weight-loss instead of below-goal.
- Equality at boundaries is inclusive where explicitly defined above.
