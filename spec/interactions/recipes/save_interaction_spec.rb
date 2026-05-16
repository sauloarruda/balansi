require "rails_helper"
require "base64"
require "tempfile"

RSpec.describe Recipes::SaveInteraction, type: :interaction do
  PNG_IMAGE = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
  ).freeze

  let(:user) { create(:user, language: "pt") }
  let(:patient) { create(:patient, user: user) }

  def recipe_parameters(attributes)
    ActionController::Parameters.new(attributes).permit!
  end

  def uploaded_recipe_image
    file = Tempfile.new([ "recipe", ".png" ])
    file.binmode
    file.write(PNG_IMAGE)
    file.rewind
    (@uploaded_recipe_image_files ||= []) << file

    Rack::Test::UploadedFile.new(file.path, "image/png", true, original_filename: "recipe.png")
  end

  def valid_attributes
    {
      name: "Lentil stew",
      ingredients: "Lentils, carrots, onion",
      instructions: "Cook until tender.",
      portion_size_grams: 200,
      calories: 450,
      proteins: 24.12,
      carbs: 60.25,
      fats: 9.38
    }
  end

  it "reanalyzes a recipe with manually provided nutrition when AI calculation is enabled" do
    recipe = patient.recipes.build
    allow(Recipes::AnalyzeNutritionInteraction).to receive(:run) do |recipe:, persist:, **|
      recipe.assign_attributes(calories: 430, proteins: 25.5, carbs: 56.25, fats: 10.75)
      instance_double(ActiveInteraction::Base, valid?: true)
    end

    result = described_class.run(
      recipe: recipe,
      user: user,
      attributes: recipe_parameters(valid_attributes)
    )

    expect(result).to be_valid
    expect(recipe).to be_persisted
    expect(recipe.calories).to eq(430)
    expect(recipe.proteins).to eq(25.5)
    expect(recipe.carbs).to eq(56.25)
    expect(recipe.fats).to eq(10.75)
    expect(Recipes::AnalyzeNutritionInteraction).to have_received(:run).with(
      recipe: recipe,
      user_id: user.id,
      user_language: user.language,
      recipe_context: [],
      persist: false,
      force: true
    )
  end

  it "passes referenced recipe nutrition to the analysis context" do
    referenced_recipe = create(
      :recipe,
      patient: patient,
      name: "Rice bowl",
      portion_size_grams: 220,
      calories: 410,
      proteins: 24.5,
      carbs: 52.25,
      fats: 9.75
    )
    recipe = patient.recipes.build

    allow(Recipes::AnalyzeNutritionInteraction).to receive(:run) do |recipe:, persist:, recipe_context:, **|
      expect(recipe_context).to eq([
        {
          recipe_name: referenced_recipe.name,
          portion_size_grams: 220.0,
          calories_per_portion: 410.0,
          proteins_per_portion: 24.5,
          carbs_per_portion: 52.25,
          fats_per_portion: 9.75
        }
      ])

      recipe.assign_attributes(calories: 430, proteins: 25.5, carbs: 56.25, fats: 10.75)
      instance_double(ActiveInteraction::Base, valid?: true)
    end

    result = described_class.run(
      recipe: recipe,
      user: user,
      attributes: recipe_parameters(
        valid_attributes.merge(
          ingredients: "Chicken and @[Rice bowl](recipe:#{referenced_recipe.id})"
        )
      )
    )

    expect(result).to be_valid
    expect(recipe).to be_persisted
  end

  it "analyzes and saves nutrition when values are missing" do
    recipe = patient.recipes.build
    allow(Recipes::AnalyzeNutritionInteraction).to receive(:run) do |recipe:, persist:, **|
      recipe.assign_attributes(calories: 430, proteins: 25.5, carbs: 56.25, fats: 10.75)
      instance_double(ActiveInteraction::Base, valid?: true)
    end

    result = described_class.run(
      recipe: recipe,
      user: user,
      attributes: recipe_parameters(valid_attributes.except(:calories, :proteins, :carbs, :fats))
    )

    expect(result).to be_valid
    expect(recipe).to be_persisted
    expect(recipe.calories).to eq(430)
    expect(Recipes::AnalyzeNutritionInteraction).to have_received(:run).with(
      recipe: recipe,
      user_id: user.id,
      user_language: user.language,
      recipe_context: [],
      persist: false,
      force: true
    )
  end

  it "does not analyze missing nutrition when AI calculation is disabled" do
    recipe = patient.recipes.build
    allow(Recipes::AnalyzeNutritionInteraction).to receive(:run)

    result = described_class.run(
      recipe: recipe,
      user: user,
      attributes: recipe_parameters(valid_attributes.except(:calories, :proteins, :carbs, :fats)),
      calculate_macros_with_ai: false
    )

    expect(result).to be_valid
    expect(recipe).to be_persisted
    expect(recipe.calories).to be_nil
    expect(Recipes::AnalyzeNutritionInteraction).not_to have_received(:run)
  end

  it "reanalyzes nutrition for an existing recipe when AI calculation is enabled" do
    recipe = create(
      :recipe,
      patient: patient,
      calories: 450,
      proteins: 24.12,
      carbs: 60.25,
      fats: 9.38
    )
    allow(Recipes::AnalyzeNutritionInteraction).to receive(:run) do |recipe:, persist:, **|
      recipe.assign_attributes(calories: 390, proteins: 21.5, carbs: 48.75, fats: 8.25)
      instance_double(ActiveInteraction::Base, valid?: true)
    end

    result = described_class.run(
      recipe: recipe,
      user: user,
      attributes: recipe_parameters(
        valid_attributes.slice(:name, :ingredients, :instructions, :portion_size_grams)
      ),
      calculate_macros_with_ai: true
    )

    expect(result).to be_valid
    expect(recipe.reload.calories).to eq(390)
    expect(recipe.proteins).to eq(21.5)
    expect(recipe.carbs).to eq(48.75)
    expect(recipe.fats).to eq(8.25)
    expect(Recipes::AnalyzeNutritionInteraction).to have_received(:run).with(
      recipe: recipe,
      user_id: user.id,
      user_language: user.language,
      recipe_context: [],
      persist: false,
      force: true
    )
  end

  it "does not persist a new recipe when AI nutrition analysis fails" do
    recipe = patient.recipes.build
    analysis_errors = ActiveModel::Errors.new(Recipe.new)
    analysis_errors.add(
      :base,
      I18n.t("patient.recipes.errors.nutrition_analysis_unavailable", locale: user.language)
    )
    allow(Recipes::AnalyzeNutritionInteraction).to receive(:run).and_return(
      instance_double(ActiveInteraction::Base, valid?: false, errors: analysis_errors)
    )

    result = described_class.run(
      recipe: recipe,
      user: user,
      attributes: recipe_parameters(valid_attributes.except(:calories, :proteins, :carbs, :fats))
    )

    expect(result).not_to be_valid
    expect(recipe).not_to be_persisted
    expect(recipe.errors.full_messages.to_sentence).to include(
      I18n.t("patient.recipes.errors.nutrition_analysis_unavailable", locale: user.language)
    )
  end

  it "attaches uploaded images after saving" do
    recipe = patient.recipes.build

    result = described_class.run(
      recipe: recipe,
      user: user,
      attributes: recipe_parameters(valid_attributes),
      images: [ uploaded_recipe_image ],
      calculate_macros_with_ai: false
    )

    expect(result).to be_valid
    expect(recipe.images.count).to eq(1)
    expect(recipe.images.first.file).to be_attached
  end

  it "rolls back recipe changes when image attachment fails" do
    recipe = create(:recipe, patient: patient, name: "Original name")
    allow_any_instance_of(described_class).to receive(:attach_images).and_raise(StandardError, "attach failed")

    expect do
      described_class.run!(
        recipe: recipe,
        user: user,
        attributes: recipe_parameters(valid_attributes.merge(name: "Updated name")),
        images: [ uploaded_recipe_image ],
        calculate_macros_with_ai: false
      )
    end.to raise_error(StandardError, "attach failed")

    expect(recipe.reload.name).to eq("Original name")
  end
end
