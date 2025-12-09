# Product Requirements Document — Journal (Balansi)

## 1. Summary

The **Journal** module is the core daily tracking experience of Balansi.
It allows patients to log meals, exercises and progress metrics, and receive AI-assisted feedback based on nutritionist-defined rules and materials.

Balansi is designed primarily for nutrition professionals. Each patient is linked to a nutritionist, who configures the scoring rules, educational materials and meal plans that guide the AI analysis.

The User Journal must be:
- fast to use,
- easy to understand,
- and reliable for daily and weekly feedback.

---

## 2. Goals & Non-Goals

### 2.1 Goals

- Allow patients to quickly log:
  - meals (with free text descriptions)
  - exercises (with free text descriptions)
  - tracking data (weight, body composition, measurements)
- Use LLM (OpenAI) to:
  - estimate macros, calories and meal commentary
  - estimate calories, NEAT and structured exercise descriptions
  - calculate daily qualitative feedback and score (1–5)
  - generate weekly summaries and guidance
- Enforce nutritionist-driven logic:
  - configurable scoring rules
  - nutritionist-provided learning materials (PDFs, videos, notes)
  - nutritionist meal plans as reusable recipes
- Provide a clear **daily** and **weekly** view of progress.

### 2.2 Non-Goals (for v1)

- Real-time device integrations (smartwatches, health APIs).
- Processing images related to meals or exercise.
- Multi-nutritionist workflows per patient.
- Advanced analytics / cohort dashboards for professionals.
- In-depth habit coaching or chat-style conversations.

---

## 3. Users & Personas

### 3.1 Patient (End User)

- Wants: simple daily logging, clear feedback, low friction.
- Needs:
  - simple forms
  - understandable comments (no medical jargon)
  - trust that the system “gets” what they ate and did

### 3.2 Nutritionist (Professional)

- Wants: structured, reliable data and AI that respects their protocol.
- Needs:
  - access their patients' journals
  - configurable daily scoring rules
  - upload of materials used as AI context (PDF, video links, notes)
  - ability to define a meal plan / menu that appears as suggested recipes
  - high-level weekly summaries to support consultations

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
- Weekly closure:
  - summary of daily balances and scores
  - trend charts for tracking data
  - weekly AI commentary
- User profile:
  - height
  - birth year
  - gender
  - primary goal
- Tracking data logging:
  - weight
  - body fat
  - muscle mass
  - water percentage
  - abdominal circumference
- Nutritionist configuration:
  - scoring rules
  - materials (PDFs, videos, notes)
  - meal plan / menu (as reusable recipes)
- Multi-language support in UI (en and pt)

### 4.2 Out of Scope (v1)

- Full admin tooling for clinic-level management.
- Notifications / reminders.
- Offline mode.

---

## 5. Functional Requirements

### 5.1 Meal Logging

**FR-ML-01**: The user can select:
- date (default: today)
- meal type: breakfast, lunch, snack, dinner

**FR-ML-02**: The user can input a free-text description of what they ate.

**FR-ML-03**: The system sends this description to the LLM with:
- user profile,
- nutritionist configs,
- nutritionist recipes,
- user recipes.

**FR-ML-04**: The LLM returns:
- proteins (g)
- carbs (g)
- fats (g)
- calories (kcal)
- estimated total gram weight
- comment about the meal

**FR-ML-05**: The meal is initially saved in **Pending** status and shown in a **review step**.

**FR-ML-06**: In the review step, the user can:
- **Accept as-is** → mark as Confirmed.
- **Adjust specific fields**:
  - calories
  - proteins
  - carbs
  - fats
  - gram weight
  - (optional) AI comment
- **Reprocess with AI**:
  - edit the description
  - ask AI to recalculate
  - receive a new proposal, still Pending until confirmed.

**FR-ML-07**: The user may save a confirmed meal as a **personal recipe** for future reuse.

**FR-ML-08**: Only **Confirmed** meals are counted in daily totals.

---

### 5.2 Exercise Logging

**FR-EX-01**: The user can input a free-text exercise description.

**FR-EX-02**: The system sends the description and basic profile to the LLM.

**FR-EX-03**: The LLM returns:
- estimated calories burned
- estimated duration
- NEAT (if applicable)
- structured description (e.g. “5 km moderate run”)

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

**FR-DC-01**: The user can tap **“Close Day”** for a given date.

**FR-DC-02**: The system:
- aggregates all **Confirmed** meals and exercises
- computes:
  - total calories consumed
  - total calories burned (basal + exercises)
  - daily caloric balance (consumed – burned)

**FR-DC-03**: The system sends daily context to the LLM:
- meals (+ macros and calories)
- exercises (+ calories)
- user profile and goal
- nutritionist scoring rules
- nutritionist materials

**FR-DC-04**: The LLM returns:
- daily score (1–5) according to nutritionist rules
- short “what went well” commentary
- short “what to improve” commentary

**FR-DC-05**: If there are **Pending** entries, the system should:
- either block closure with a warning
- or allow closure but clearly show that pending entries are ignored

Decision for v1:
- Show a warning with number of pending entries and allow closure anyway.

---

### 5.4 Weekly Closure

**FR-WC-01**: A “Weekly Summary” view is available.

**FR-WC-02**: The weekly view shows:
- all days in the selected week
- daily caloric balance for each day
- daily score for each day

**FR-WC-03**: The user can select which tracking metric to see as a **chart**:
- weight
- body fat
- muscle mass
- water
- abdominal circumference

**FR-WC-04**: The system sends weekly context to the LLM, including:
- daily balances
- daily scores
- tracking data points
- user profile and goal

**FR-WC-05**: The LLM returns:
- estimated weight change (if meaningful)
- how the week impacted health / goals
- short guidance for the next week

---

### 5.5 User Profile

**FR-UP-01**: The user must be able to set:
- height
- birth year
- gender (male / female)
- primary goal:
  - fat loss
  - muscle gain
  - disease treatment

**FR-UP-02**: Profile changes should affect:
- basal metabolism estimation
- AI feedback tone and focus

---

### 5.6 Tracking Data

**FR-TR-01**: The user can periodically log:
- weight
- body fat
- muscle mass
- water
- abdominal circumference

**FR-TR-02**: Tracking entries are tied to a date.

**FR-TR-03**: Tracking data feeds into:
- daily view (latest snapshot)
- weekly chart
- weekly AI summary

---

### 5.7 Nutritionist Configuration

**FR-NT-01**: The nutritionist can configure:
- scoring rules for daily score (1–5)
  - e.g. target protein range, deficit, alcohol rules, training rules

**FR-NT-02**: The nutritionist can submit materials:
- PDF uploads
- video links
- text notes

**FR-NT-03**: The nutritionist can define a meal plan / menu:
- structured set of recommended meals
- these appear as **professional recipes** for the patient

**FR-NT-04**: All nutritionist configurations must be used as context in LLM prompts.

---

## 6. User Flows

### 6.1 Flow: Log a Meal

1. User opens “Daily Journal” for today.
2. Taps “Add Meal”.
3. Selects meal type (default based on time).
4. Types description in free text.
5. Submits.
6. System calls LLM and shows a **review screen**:
   - macros
   - calories
   - gram weight
   - comment
7. User:
   - accepts, or
   - edits fields and saves, or
   - edits description and reprocesses with AI.
8. On accept or save:
   - meal becomes **Confirmed**
   - daily totals update.

### 6.2 Flow: Log an Exercise

1. User opens “Daily Journal”.
2. Taps “Add Exercise”.
3. Types description.
4. System calls LLM and shows:
   - duration
   - calories
   - NEAT
   - structured description
5. User:
   - accepts, or
   - adjusts fields, or
   - reprocesses with new description.
6. On confirm, exercise is saved and included in energy expenditure.

### 6.3 Flow: Close Day

1. User opens Daily Journal for a specific date.
2. Sees:
   - list of meals and exercises (with status)
   - current totals
3. If there are Pending entries:
   - warning: “You have X unconfirmed items.”
4. User taps “Close Day”.
5. System calculates balance and calls LLM.
6. User sees:
   - daily balance
   - score
   - “what went well”
   - “what to improve”.

### 6.4 Flow: Weekly Summary

1. User opens “Weekly Summary”.
2. Selects week (default: current week).
3. Sees:
   - table of days with balance + score
4. Selects metric to chart (weight, fat, etc.).
5. System calls LLM with weekly context.
6. User sees:
   - weekly comment
   - estimated change
   - guidance.

---

## 7. Screens (High-Level)

### 7.1 Daily Journal Screen

- Date selector (day)
- Summary:
  - total calories in
  - total calories out
  - balance
  - last score (if day is closed)
- Sections:
  - Meals list (with status badges: Pending / Confirmed)
  - Exercises list (with status badges)
  - Tracking snapshot (optional, latest values)
- Actions:
  - Add Meal
  - Add Exercise
  - Add Tracking data
  - Close Day

### 7.2 Meal Entry / Review Screen

- Fields:
  - Date (default today)
  - Meal type
  - Free text description (editable)
- After AI:
  - Macros, calories, gram weight, comment
  - Status banner: “AI suggestion”
- Actions:
  - Confirm meal
  - Edit values
  - Edit description & Reprocess
  - Save as personal recipe (after confirmation)

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

### 7.4 Tracking Data Screen

- Date
- Weight
- Body fat
- Muscle
- Water
- Abdominal circumference
- History list (recent entries)

### 7.5 Weekly Summary Screen

- Week selector
- Table of days:
  - score
  - caloric balance
- Metric selector:
  - weight, fat, muscle, water, abdominal
- Chart area
- Weekly AI summary card.

### 7.6 Nutritionist Configuration Screens (High level)

- Scoring Rules:
  - forms to define thresholds and scoring logic
- Materials:
  - upload of PDFs
  - adding links
  - text notes
- Meal Plan:
  - list of recommended meals / recipes
  - ability to assign to patients.

---

## 8. Non-Functional Requirements (high-level)

- Fast interactions (AI calls aside).
- UI must handle AI failures:
  - show errors
  - allow manual entry / override.
- Data consistency:
  - only Confirmed entries are used in summaries.
- Privacy:
  - patient data must be isolated per nutritionist / clinic.
