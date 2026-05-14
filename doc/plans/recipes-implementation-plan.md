# Recipes Implementation Plan

Source PRD: `doc/recipes/prd.md`

## Goal

Implement private recipe management, recipe image handling, meal journal recipe mentions, proportional macro calculation, and professional read-only visibility while keeping each pull request small enough to review safely.

Target pull request size: approximately 500 changed lines or less per PR.

## Branch And PR Workflow

Branch naming pattern:

```text
BAL-22.${phase}-${description}
```

Rules:

- `phase` is the two-digit PR number: `01`, `02`, `03`, and so on.
- `description` is a short hyphen-separated summary of the phase, for example `model-migration`, `crud-backend`, or `recipe-library-ui`.
- Each phase should be implemented on its own branch.
- After implementation is complete for a phase, review the full code diff before creating the pull request.
- Only create the pull request after the review is complete and any requested fixes are applied.

Examples:

- `BAL-22.01-model-migration`
- `BAL-22.02-crud-backend`
- `BAL-22.03-recipe-library-ui`

## Technical Direction

- Model recipes as patient-owned records: `Recipe belongs_to :patient`.
- Keep recipes private in v1. A patient can manage only their own recipes.
- Use `ActiveStorage` for recipe images.
- Store recipe macro values per portion on the recipe and use `portion_size_grams` to calculate proportional values by gram amount.
- Do not rely only on meal description text for historical accuracy. Persist recipe references used by meals with a snapshot of the recipe nutrition data at logging time.
- Inject recipe context into meal LLM analysis only when the meal description references recipes.
- Preserve Rails i18n rules by updating `config/locales/pt.yml` and `config/locales/en.yml` together for all user-facing copy.

## Phase 1: Recipe Data Model

Status: Complete.

Purpose: create the persistence foundation with no UI.

Scope:

- Add `recipes` table.
- Add `Recipe` model.
- Add `Patient has_many :recipes`.
- Add validations:
  - `name` required.
  - `ingredients` required.
  - `instructions` optional.
  - `portion_size_grams` required and greater than 0.
  - macro fields numeric when present, representing one portion.
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
- A recipe without name, ingredients, or valid portion size is invalid.
- Recipe macros represent one portion and gram-based helpers calculate proportional values from `portion_size_grams`.

Implementation status:

- `recipes` table and decimal macro migrations are in place.
- `Recipe` belongs to `Patient`; `Patient` owns dependent recipes.
- Recipe validations cover required name, ingredients, portion size, macro ranges, and decimal precision.
- Per-portion and gram-proportional nutrition helpers are implemented on `Recipe`.
- Factory and model specs cover associations, validations, optional instructions, optional macros, and proportional macro calculations.

Estimated size: 150-250 changed lines.

## Phase 2: Recipe CRUD Backend

Status: Complete.

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

Implementation status:

- `patient/recipes` routes added.
- `Patients::RecipesController` handles full CRUD for patient-owned recipes.
- Recipe lookups are scoped through `current_patient.recipes`.
- Controller specs cover CRUD behavior and ownership isolation.
- Flash messages and view copy are translated in English and Portuguese.

Estimated size: 250-400 changed lines.

## Phase 3: Recipe Library UI

Status: Complete.

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
- Show macros per portion and portion size in grams.
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

Implementation status:

- Recipe library index now renders a patient-facing card grid and translated empty state.
- Recipe detail page shows ingredients, instructions, portion size, and nutrition per portion.
- New and edit views use a structured form with translated helper copy.
- Application layout includes top-nav and drawer entries for patient recipes.
- Request/controller specs cover navigation, ownership isolation, CRUD rendering, and per-portion macro display.

Estimated size: 350-500 changed lines.

## Phase 4: Recipe Images With ActiveStorage

Status: Complete.

Purpose: add recipe image upload and optimized variants independently from the base CRUD.

Scope:

- Add ActiveStorage migrations if not already installed.
- Add `Image` model with ActiveStorage attachment variants.
- Add `Recipe has_many :images`.
- Permit multiple image uploads in recipe forms.
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

- A patient can upload images for a recipe.
- Recipe list and detail pages display optimized image variants.
- Test environment stores uploads on disk.

Implementation status:

- ActiveStorage tables added through the Rails-generated migration.
- `Image` stores the ActiveStorage attachment and thumbnail, standard, and large variants.
- `Recipe` owns many images.
- Recipe forms permit and upload multiple images.
- Recipe cards render thumbnail carousels and detail pages render standard images linked to the large variant.
- Test, local, staging, and production storage remain on disk, matching the existing Kamal persistent volume setup.
- Model and controller specs cover image attachment, upload, and rendered image variants.

Estimated size: 250-450 changed lines.

## Phase 5: Recipe Nutrition Analysis

Status: Complete.

Purpose: calculate recipe macro values per portion from ingredients and portion size through AI, while allowing manual override.

Scope:

- Add recipe nutrition analysis interaction.
- Add recipe nutrition analysis client, following the existing meal analysis client pattern.
- Skip AI analysis when all macro fields were manually provided before save.
- Save per-portion calories, proteins, carbs, and fats on the recipe.
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

Implementation status:

- `Recipes::NutritionAnalysisClient` follows the existing chat-completion client pattern and sends recipe name, ingredients, instructions, portion size, and language context.
- `Recipes::AnalyzeNutritionInteraction` handles AI calls, response normalization, retry behavior, rate limiting, Sentry reporting, translated errors, and per-portion nutrition assignment.
- `Recipes::SaveInteraction` owns recipe assignment, validation, AI analysis orchestration, transaction handling, and image attachment.
- Patient recipe create/update runs AI analysis only when one or more nutrition fields are blank.
- Recipes with all nutrition fields supplied manually skip AI analysis, including later manual edits.
- Recipe create rolls back cleanly when AI analysis fails, so partial recipes are not persisted.
- Specs cover successful analysis, manual skip, unsaved assignment for controller transactions, malformed responses, unexpected errors, retries, rate limits, client payload behavior, and controller integration.

Estimated size: 300-500 changed lines.

## Phase 6: Recipe Search Endpoint

Status: Complete.

Purpose: provide a small backend API for the meal mention picker.

Scope:

- Add JSON endpoint for patient-owned recipe search.
- Suggested route: `GET /patient/recipes/search?q=bolo`.
- Return only picker data:
  - `id`
  - `name`
  - `thumbnail_url`
  - per-portion macros
  - `portion_size_grams`
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

Implementation status:

- `GET /patient/recipes/search?q=...` returns JSON picker payloads for current patient recipes only.
- `Recipes::SearchInteraction` owns the patient-scoped name-prefix search, ordering, image preloading, and 10-result limit.
- Response payload is limited to recipe id, name, thumbnail URL, per-portion nutrition, and portion size.
- The existing `recipes_patient_name_idx` composite index supports patient-scoped name search.
- Interaction and request specs cover ownership isolation, JSON shape, result limit, ordering, and blank queries.

Estimated size: 150-300 changed lines.

## Phase 7: Meal Recipe Mention Picker UI

Status: Complete.

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

Implementation status:

- `Recipe::MENTION_*` constants define the shared structured reference format.
- `recipe_mentions_controller.js` powers the contenteditable meal description editor, search debounce, mouse selection, keyboard selection, chip rendering, and hidden-field serialization.
- Meal description forms render the mention editor with translated loading, empty, and error states.
- Saved structured references are rehydrated as visual chips when editing or re-rendering meal forms.
- Controller/request specs cover the meal form wiring, and JavaScript controller specs cover serialization, rehydration, structured reference generation, and recent-recipe search behavior.

Estimated size: 250-450 changed lines.

## Phase 8: Persist Meal Recipe References

Status: Complete.

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
  - `portion_size_grams`
  - `calories_per_portion`
  - `proteins_per_portion`
  - `carbs_per_portion`
  - `fats_per_portion`
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

Implementation status:

- `meal_recipe_references` table stores durable meal-owned recipe snapshots with nullable `recipe_id`.
- `MealRecipeReference` validates snapshot nutrition and portion size.
- `Meal has_many :meal_recipe_references`; `Recipe has_many :meal_recipe_references, dependent: :nullify`.
- `Journal::ResolveRecipeReferencesInteraction` parses structured mentions, resolves recipes through `patient.recipes`, snapshots nutrition fields, keeps repeated mentions, and replaces references on description changes.
- Meal create and reprocess flows sync recipe references transactionally before analysis.
- Specs cover snapshot creation, ownership isolation, replacement behavior, repeated mentions, create/reprocess integration, and historical readability after recipe edits or deletion.

Estimated size: 300-500 changed lines.

## Phase 9: Inject Recipe Context Into Meal Analysis

Status: Complete.

Purpose: fulfill the PRD requirement that the LLM receives exact recipe nutrition context.

Scope:

- Update `Journal::AnalyzeMealInteraction` to gather resolved recipe references.
- Update `Journal::MealAnalysisClient#analyze` to accept optional recipe context.
- Add prompt content with:
  - recipe name
  - portion size in grams
  - per-portion macros
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

Implementation status:

- `Journal::AnalyzeMealInteraction` gathers persisted `meal_recipe_references` snapshots ordered by id.
- Meal analysis sends `recipe_context` only when references exist, preserving the existing client call shape for meals without recipe mentions.
- `Journal::MealAnalysisClient#analyze` accepts optional recipe context and sends structured JSON prompts with role, source-of-truth priority, operational contract, response schema, validation rules, meal data, and recipe snapshots.
- Client prompt specs verify recipe context inclusion and absence when no references are present.
- Interaction specs verify recipe context is passed from persisted meal references into the LLM client.

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

1. `BAL-22.01-model-migration`
2. `BAL-22.02-crud-backend`
3. `BAL-22.03-recipe-library-ui`
4. `BAL-22.04-recipe-images`
5. `BAL-22.05-nutrition-analysis`
6. `BAL-22.06-search-endpoint`
7. `BAL-22.07-mentions-ui`
8. `BAL-22.08-meal-recipe-references`
9. `BAL-22.09-meal-analysis-context`
10. `BAL-22.10-professional-visibility`
11. `BAL-22.11-polish-system-tests`

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
