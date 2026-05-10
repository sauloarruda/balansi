# Recipes Implementation Plan

Source PRD: `doc/recipes/prd.md`

## Goal

Implement private recipe management, recipe image handling, meal journal recipe mentions, proportional macro calculation, and professional read-only visibility while keeping each pull request small enough to review safely.

Target pull request size: approximately 500 changed lines or less per PR.

## Technical Direction

- Model recipes as patient-owned records: `Recipe belongs_to :patient`.
- Keep recipes private in v1. A patient can manage only their own recipes.
- Use `ActiveStorage` for recipe images.
- Store recipe macro totals on the recipe and derive per-portion values from `yield_portions`.
- Do not rely only on meal description text for historical accuracy. Persist recipe references used by meals with a snapshot of the recipe nutrition data at logging time.
- Inject recipe context into meal LLM analysis only when the meal description references recipes.
- Preserve Rails i18n rules by updating `config/locales/pt.yml` and `config/locales/en.yml` together for all user-facing copy.

## Phase 1: Recipe Data Model

Purpose: create the persistence foundation with no UI.

Scope:

- Add `recipes` table.
- Add `Recipe` model.
- Add `Patient has_many :recipes`.
- Add validations:
  - `name` required.
  - `ingredients` required.
  - `yield_portions` required and greater than or equal to 1.
  - macro fields numeric when present.
- Add per-portion helper methods:
  - `calories_per_portion`
  - `proteins_per_portion`
  - `carbs_per_portion`
  - `fats_per_portion`
- Add factory and model specs.

Likely files:

- `db/migrate/*_create_recipes.rb`
- `app/models/recipe.rb`
- `app/models/patient.rb`
- `spec/models/recipe_spec.rb`
- `spec/factories/recipes.rb`
- `config/locales/pt.yml`
- `config/locales/en.yml`

Tests:

```bash
bundle exec rspec spec/models/recipe_spec.rb
```

Acceptance criteria:

- A valid recipe belongs to a patient.
- A recipe without name, ingredients, or valid yield is invalid.
- Per-portion macros are calculated from total macros and yield.

Estimated size: 150-250 changed lines.

## Phase 2: Recipe CRUD Backend

Purpose: add routes, controller behavior, and authorization boundaries before building the polished UI.

Scope:

- Add `patient/recipes` routes.
- Add `Patients::RecipesController`.
- Implement `index`, `show`, `new`, `create`, `edit`, `update`, and `destroy`.
- Scope all lookups through `current_patient.recipes`.
- Add translated flash messages and validation errors as needed.
- Add controller or request specs for CRUD and ownership isolation.

Likely files:

- `config/routes.rb`
- `app/controllers/patients/recipes_controller.rb`
- `spec/controllers/patients/recipes_controller_spec.rb` or `spec/requests/patient_recipes_spec.rb`
- `config/locales/pt.yml`
- `config/locales/en.yml`

Tests:

```bash
bundle exec rspec spec/controllers/patients/recipes_controller_spec.rb
```

Acceptance criteria:

- A patient can create, update, view, list, and delete their own recipes through the controller.
- A patient cannot access recipes owned by another patient.

Estimated size: 250-400 changed lines.

## Phase 3: Recipe Library UI

Purpose: add the patient-facing recipe management experience without image upload yet.

Scope:

- Add Slim views for recipe library:
  - `index`
  - `show`
  - `new`
  - `edit`
  - `_form`
  - `_recipe_card`
- Add a recipe navigation entry to the application layout.
- Show macros per portion and recipe yield.
- Add an empty state.
- Keep all user-facing copy in i18n.

Likely files:

- `app/views/patients/recipes/index.html.slim`
- `app/views/patients/recipes/show.html.slim`
- `app/views/patients/recipes/new.html.slim`
- `app/views/patients/recipes/edit.html.slim`
- `app/views/patients/recipes/_form.html.slim`
- `app/views/patients/recipes/_recipe_card.html.slim`
- `app/views/layouts/application.html.slim`
- `config/locales/pt.yml`
- `config/locales/en.yml`

Tests:

```bash
bundle exec rspec spec/requests/patient_recipes_spec.rb
```

Acceptance criteria:

- A patient can navigate to recipes from the app layout.
- A patient can create, edit, view, and delete recipes from the UI.
- Views do not hardcode user-facing strings.

Estimated size: 350-500 changed lines.

## Phase 4: Recipe Images With ActiveStorage

Purpose: add cover image upload and optimized variants independently from the base CRUD.

Scope:

- Add ActiveStorage migrations if not already installed.
- Add `Recipe has_one_attached :image`.
- Permit image upload in recipe forms.
- Display image variants:
  - thumbnail, approximately 100x100 cropped square.
  - standard, approximately 600x400.
  - large/zoom, maximum approximately 1200x800.
- Configure S3 storage for production and staging if needed.
- Keep test and local environments on disk storage.
- Add attachment specs.

Likely files:

- ActiveStorage migrations, if missing.
- `app/models/recipe.rb`
- recipe form and display views.
- `config/storage.yml`
- environment storage config, if needed.
- request/model specs with uploaded fixture.

Tests:

```bash
bundle exec rspec spec/models/recipe_spec.rb
bundle exec rspec spec/requests/patient_recipes_spec.rb
```

Acceptance criteria:

- A patient can upload a cover image for a recipe.
- Recipe list and detail pages display optimized image variants.
- Test environment stores uploads on disk.

Estimated size: 250-450 changed lines.

## Phase 5: Recipe Nutrition Analysis

Purpose: calculate recipe macro totals from ingredients through AI, while allowing manual override.

Scope:

- Add recipe nutrition analysis interaction.
- Add recipe nutrition analysis client, following the existing meal analysis client pattern.
- Skip AI analysis when all macro fields were manually provided before save.
- Save total calories, proteins, carbs, and fats on the recipe.
- Keep manual edits possible after AI analysis.
- Add retry/error handling consistent with meal analysis.
- Add specs with mocked client responses.

Likely files:

- `app/interactions/recipes/analyze_nutrition_interaction.rb`
- `app/services/recipes/nutrition_analysis_client.rb`
- `app/controllers/patients/recipes_controller.rb`
- `spec/interactions/recipes/analyze_nutrition_interaction_spec.rb`
- `spec/services/recipes/nutrition_analysis_client_spec.rb`
- `config/locales/pt.yml`
- `config/locales/en.yml`

Tests:

```bash
bundle exec rspec spec/interactions/recipes/analyze_nutrition_interaction_spec.rb
bundle exec rspec spec/services/recipes/nutrition_analysis_client_spec.rb
```

Acceptance criteria:

- A recipe without macros triggers AI nutrition analysis.
- A recipe with manually provided macros does not trigger AI analysis.
- Users can edit AI-generated macros manually.
- AI failures are surfaced through translated errors without corrupting the recipe.

Estimated size: 300-500 changed lines.

## Phase 6: Recipe Search Endpoint

Purpose: provide a small backend API for the meal mention picker.

Scope:

- Add JSON endpoint for patient-owned recipe search.
- Suggested route: `GET /patient/recipes/search?q=bolo`.
- Return only picker data:
  - `id`
  - `name`
  - `thumbnail_url`
  - per-portion macros
  - `yield_portions`
- Search by recipe name.
- Limit results, for example to 10.
- Add request specs for ownership isolation and JSON shape.

Likely files:

- `config/routes.rb`
- `app/controllers/patients/recipes/search_controller.rb` or a search action under `Patients::RecipesController`
- `spec/requests/patient_recipe_search_spec.rb`

Tests:

```bash
bundle exec rspec spec/requests/patient_recipe_search_spec.rb
```

Acceptance criteria:

- Search returns only recipes owned by the current patient.
- Search response contains only the fields needed by the picker.
- Search has an index strategy suitable for `patient_id` and `name`.

Estimated size: 150-300 changed lines.

## Phase 7: Meal Recipe Mention Picker UI

Purpose: support `@` recipe mentions in the new meal form.

Scope:

- Add a Stimulus controller for recipe mentions.
- Connect it to the meal description textarea.
- When the user types `@` followed by text, show matching recipes.
- Support mouse selection and basic keyboard selection.
- Insert a structured reference into the textarea.
- Recommended internal format: `@[Recipe Name](recipe:123)`.
- Keep the visible flow simple enough for v1.

Likely files:

- `app/javascript/controllers/recipe_mentions_controller.js`
- `app/javascript/controllers/index.js`
- `app/views/journal_entries/meals/new.html.slim`
- `config/locales/pt.yml`
- `config/locales/en.yml`

Tests:

```bash
bundle exec rspec spec/requests/patient_recipe_search_spec.rb
```

Manual verification:

- Open the new meal form.
- Type `@`.
- Confirm the dropdown appears.
- Select a recipe.
- Confirm the structured reference is inserted.

Acceptance criteria:

- Typing `@` opens a recipe picker.
- Filtering works by typed text.
- Selecting a recipe inserts a parseable reference.
- Existing meal creation still works without a recipe mention.

Estimated size: 250-450 changed lines.

## Phase 8: Persist Meal Recipe References

Purpose: turn recipe mentions into durable meal data and preserve historical nutrition context.

Scope:

- Add `meal_recipe_references` table.
- Add `MealRecipeReference` model.
- Add associations:
  - `Meal has_many :meal_recipe_references`
  - `MealRecipeReference belongs_to :meal`
  - `MealRecipeReference belongs_to :recipe, optional: true`
- Store recipe snapshot fields:
  - `recipe_id`
  - `recipe_name`
  - `yield_portions`
  - `total_calories`
  - `total_proteins`
  - `total_carbs`
  - `total_fats`
  - `portion_quantity`
- Add parser or interaction to extract `@[Name](recipe:id)` references.
- Resolve references only through the current patient's recipes.
- Attach references during meal create and reprocess flows.

Likely files:

- `db/migrate/*_create_meal_recipe_references.rb`
- `app/models/meal_recipe_reference.rb`
- `app/models/meal.rb`
- `app/interactions/journal/resolve_recipe_references_interaction.rb` or service object.
- specs for model and parser/service.

Tests:

```bash
bundle exec rspec spec/models/meal_recipe_reference_spec.rb
bundle exec rspec spec/interactions/journal/resolve_recipe_references_interaction_spec.rb
```

Acceptance criteria:

- A valid recipe mention creates a meal recipe reference snapshot.
- Recipes owned by other patients are ignored or rejected.
- Historical meal references remain readable if the recipe is later edited or deleted.

Estimated size: 300-500 changed lines.

## Phase 9: Inject Recipe Context Into Meal Analysis

Purpose: fulfill the PRD requirement that the LLM receives exact recipe nutrition context.

Scope:

- Update `Journal::AnalyzeMealInteraction` to gather resolved recipe references.
- Update `Journal::MealAnalysisClient#analyze` to accept optional recipe context.
- Add prompt content with:
  - recipe name
  - total yield portions
  - total macros
  - per-portion macros
  - referenced portion quantity when available
- Preserve existing behavior when no recipe references exist.
- Add specs for interaction and client payload.

Likely files:

- `app/interactions/journal/analyze_meal_interaction.rb`
- `app/services/journal/meal_analysis_client.rb`
- `spec/interactions/journal/analyze_meal_interaction_spec.rb`
- `spec/services/journal/meal_analysis_client_spec.rb`

Tests:

```bash
bundle exec rspec spec/interactions/journal/analyze_meal_interaction_spec.rb
bundle exec rspec spec/services/journal/meal_analysis_client_spec.rb
```

Acceptance criteria:

- Meals with recipe references send recipe context to the LLM.
- Meals without recipe references use the existing prompt shape.
- Existing meal analysis specs continue passing.

Estimated size: 200-400 changed lines.

## Phase 10: Patient And Professional Recipe Visibility In Journals

Purpose: show recipe details where meals are reviewed, including professional read-only journal access.

Scope:

- Update meal cards and review pages to display referenced recipes.
- For patients, link to the recipe detail page where appropriate.
- For professionals, show recipe details read-only inside the patient journal or through a read-only route.
- Ensure professional access uses existing patient authorization rules.
- Add specs for professional visibility.

Likely files:

- `app/views/journal_entries/meals/_meal.html.slim`
- `app/views/journal_entries/meals/show.html.slim`
- professional patient journal views or controller if a read-only detail route is needed.
- request/controller specs.

Tests:

```bash
bundle exec rspec spec/controllers/professionals/patients/journals_controller_spec.rb
```

Acceptance criteria:

- Patients can see the recipe details used by a meal.
- Professionals with access can see recipe details in the patient's journal.
- Professionals without access cannot see recipe details.

Estimated size: 250-450 changed lines.

## Phase 11: Polish, Performance, And Hardening

Purpose: close usability, performance, and full-flow test gaps after the feature is functionally complete.

Scope:

- Decide whether to preload recipes in the meal form to meet the sub-100ms picker target.
- Add or refine indexes if search performance needs it.
- Add empty/error states to the picker.
- Improve mobile behavior.
- Add end-to-end system coverage when practical:
  - create recipe.
  - mention recipe in a meal.
  - analyze meal.
  - confirm meal.
  - professional views patient journal.
- Run security and style checks.

Tests:

```bash
bundle exec rspec
bundle exec rubocop
bundle exec brakeman
```

Acceptance criteria:

- Main recipe-to-meal flow is covered.
- Picker remains usable on mobile.
- No obvious security or lint regressions remain.

Estimated size: split into multiple PRs if this exceeds 500 changed lines.

## Recommended PR Sequence

1. `BAL-xxx-recipe-model`
2. `BAL-xxx-recipe-crud-backend`
3. `BAL-xxx-recipe-library-ui`
4. `BAL-xxx-recipe-images`
5. `BAL-xxx-recipe-nutrition-analysis`
6. `BAL-xxx-recipe-search-endpoint`
7. `BAL-xxx-meal-recipe-mentions-ui`
8. `BAL-xxx-meal-recipe-references`
9. `BAL-xxx-meal-analysis-recipe-context`
10. `BAL-xxx-professional-recipe-visibility`
11. `BAL-xxx-recipes-polish-system-tests`

## Main Risks

- Nutrition accuracy can degrade if proportional recipe calculation is left entirely to the LLM. Persisting recipe reference snapshots reduces this risk.
- Recipe edits and deletes can otherwise alter historical meal interpretation. Snapshot fields prevent that.
- The mention picker can grow large if all recipes are preloaded. Start with the search endpoint and move to preload only if latency requires it.
- UI and i18n changes can push PRs over 500 lines. Keep visual polish separate from backend behavior.

## Deferred V1 Decisions

- Public recipe sharing.
- Professional-created recipes assigned to patients.
- Recipe import from URLs.
- Advanced tags and categories.
- Food database moderation or deduplication workflows.
