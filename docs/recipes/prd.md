# Product Requirements Document — Recipes (Balansi)

## 1. Summary

The **Recipes** feature enables users to create, manage, and reuse private food recipes within Balansi. Users can seamlessly log these recipes in their daily journals by using an `@` mention recipe picker in the meal description. The system will automatically calculate portion macros based on the recipe's saved nutritional profile and user input.

In v1, the module introduces:
- Private recipe creation and management (CRUD).
- `@` mention recipe picker in the meal journal entry form.
- Automated portion calculations during meal analysis.
- Image management using S3 with optimized variants.
- Recipe visibility restricted to the creator (private only).
- Professional visibility of patient recipes via the Patient Journal.

---

## 2. Goals & Non-Goals

### 2.1 Goals

- Allow users to create private recipes with a name, instructions, list of ingredients, and portion yield.
- Allow users to upload and manage recipe images (stored in S3 with optimized variants).
- Enable quick logging of recipes in the meal journal using an `@` mention autocomplete picker.
- Automatically calculate the nutritional value of logged portions (e.g., if a recipe yields 4 portions and the user logs 1 portion, the system logs 25% of the total macros).
- Provide a responsive grid UI to manage the personal recipe library.
- **Long-term Vision (Food Database):** Serve as a foundational building block for a tagged food database. By collecting user descriptions, macro information, and high-quality images, this module will gradually build a dataset to train future ML models for automated food image recognition.

### 2.2 Non-Goals (for v1)

- Public recipe sharing or community recipe database.
- Professional creating recipes and assigning them directly to patients.
- Automatic importing of recipes from external websites via URL.
- Advanced recipe tags/categorization (e.g., "vegan", "keto") beyond basic text search.

---

## 3. Users & Personas

### 3.1 Patient

- **Wants:** to save time by reusing frequent meals/recipes instead of typing them out every day.
- **Needs:** a simple way to create recipes, add photos, and mention them in the daily journal.

### 3.2 Professional

- **Wants:** to see exactly what the patient ate, including the detailed breakdown of custom recipes.
- **Needs:** read-only access to view the recipes used in the patient's journal.

---

## 4. Scope

### 4.1 In Scope

- **Recipe Management (CRUD):** Name, Description/Instructions, Ingredients (free text), Yield (number of portions), macros per portion.
- **Image Management:** Upload to S3 via ActiveStorage, displaying optimized variants.
- **Journal Integration:** `@` mention picker in the `meal_description` text area on the "New Meal" form.
- **Automated Calculation:** AI and system logic to parse "@My Recipe (1 portion)" and accurately map the correct macros.
- **Professional Access:** Professionals viewing a Patient's Journal can see the referenced recipe details.

---

## 5. Functional Requirements

### 5.1 Recipe CRUD

- **FR-REC-01:** A user must be able to create, read, update, and delete their own recipes.
- **FR-REC-02:** A recipe must include: `name` (required), `ingredients` (required), `instructions` (optional), `yield_portions` (required, min 1), `image` (optional).
- **FR-REC-03:** The system must calculate the total nutritional value (Calories, Protein, Carbs, Fat) of the recipe upon creation via AI analysis of the ingredients.
  - If the user has already manually filled out the macros before saving, the AI analysis must be skipped.
  - The user must always be able to manually edit and override the AI-calculated macros after the analysis is complete.

### 5.2 Image Management

- **FR-IMG-01:** Users can upload a cover image for their recipe.
- **FR-IMG-02:** The system must upload the image to an S3 bucket.
- **FR-IMG-03:** The system must generate optimized variants for different UI contexts:
  - **Thumbnail (Search/Picker):** e.g., 100x100px (cropped/square) for the `@` mention dropdown and small list views.
  - **Standard (View/Grid):** e.g., 600x400px for the recipe grid and detail page inline view.
  - **Zoom (Original/Large):** e.g., 1200x800px max, for when the user clicks the photo to expand it.

### 5.3 Meal Journal Integration

- **FR-JNL-01:** The "New Meal" form (`meal_description` textarea) must support an autocomplete trigger using the `@` character.
- **FR-JNL-02:** Typing `@` followed by text must search the user's private recipes and display a dropdown/picker.
- **FR-JNL-03:** Selecting a recipe from the picker must insert a structured reference (e.g., `@[Recipe Name](id)`) into the text.
- **FR-JNL-04:** When processing the meal log via AI, the system must explicitly inject the recipe's contextual data (total yield portions and total macros) into the LLM prompt. This ensures the LLM understands the exact nutritional value to apply proportionally based on the user's logged amount.

---

## 6. User Flows

### 6.1 Flow: Create a New Recipe

1. User navigates to the "Recipes" section from the sidebar.
2. User clicks "New Recipe".
3. System displays the recipe form.
4. User enters name, ingredients, instructions, yield portions, and uploads an image.
5. User clicks "Save".
6. System analyzes the ingredients to calculate total macros, uploads the image to S3, and saves the recipe.
7. User sees the new recipe in their grid view.

### 6.2 Flow: Log a Meal using a Recipe

1. User clicks "Adicionar Refeição" on Today's Journal.
2. In the "Descrição" text area, user types "Eu comi 1 porção de @"
3. System shows a dropdown of user's recipes.
4. User selects "Bolo de Banana". The text area updates to "Eu comi 1 porção de @Bolo de Banana".
5. User clicks "Analisar com IA".
6. System parses the text, recognizes the recipe reference and the "1 porção" quantity.
7. System calculates the macros (1 / total yield * total macros) and presents the review screen.
8. User confirms and the meal is logged.

---

## 7. Wireframes (Representations)

### 7.1 Recipes List View

```text
+---------------------------------------------------------+
| [Menu]  Recipes                              [+ Recipe] |
|---------------------------------------------------------|
|                                                         |
|  +----------------+  +----------------+                 |
|  | [ Image ]      |  | [ Image ]      |                 |
|  | Bolo de Banana |  | Frango Fit     |                 |
|  | 200 kcal/porç  |  | 350 kcal/porç  |                 |
|  | 4 porções      |  | 2 porções      |                 |
|  +----------------+  +----------------+                 |
|                                                         |
+---------------------------------------------------------+
```

### 7.2 New Meal Form with @ Mention

```text
+---------------------------------------------------------+
| Adicionar Refeição                                      |
|---------------------------------------------------------|
| Data: [ 2026-05-10 ]                                    |
| Tipo: [ Almoço v ]                                      |
|                                                         |
| Descrição:                                              |
| +-----------------------------------------------------+ |
| | Eu comi 1 porção de @bolo                           | |
| |                      +----------------------------+ | |
| |                      | 🍰 Bolo de Banana          | | |
| |                      | 🍗 Bolo de Carne           | | |
| |                      +----------------------------+ | |
| +-----------------------------------------------------+ |
|                                                         |
| [ Analisar com IA ] [ Cancelar ]                        |
+---------------------------------------------------------+
```

---

## 8. Non-Functional Requirements

### 8.1 Performance

- The `@` mention autocomplete must respond in under 100ms. Consider pre-loading the user's recipe names in a JS controller (e.g., Stimulus autocomplete) to avoid network latency on every keystroke.

### 8.2 Storage & Infrastructure

- Images must be processed asynchronously using ActiveStorage variants to prevent request blocking.
- Images must be stored in AWS S3 as configured in the production environment.

---

## 9. Acceptance Criteria

- A user can create a recipe with an image and view it on a dedicated recipes page.
- Images are correctly uploaded to S3 and served via optimized variants.
- On the New Meal form, typing `@` triggers a dropdown of the user's saved recipes.
- Logging a meal with a recipe reference correctly calculates the macros based on the fraction of portions consumed.
- Professionals can view the recipe details when reviewing a patient's meal log.

---

## 10. References

- Original Request: Developing a Recipe Management System
- Professional PRD Context: [Professional PRD](../professional/prd.md)

---

**Document Version**: 1.0
**Last Updated**: 2026-05-10
**Status**: Draft
