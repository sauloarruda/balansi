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

  it "saves a recipe with manually provided nutrition without AI analysis" do
    recipe = patient.recipes.build
    allow(Recipes::AnalyzeNutritionInteraction).to receive(:run)

    result = described_class.run(
      recipe: recipe,
      user: user,
      attributes: recipe_parameters(valid_attributes)
    )

    expect(result).to be_valid
    expect(recipe).to be_persisted
    expect(recipe.proteins).to eq(24.12)
    expect(Recipes::AnalyzeNutritionInteraction).not_to have_received(:run)
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
      persist: false
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

  it "does not persist a new recipe when AI nutrition analysis fails" do
    recipe = patient.recipes.build
    analysis_errors = ActiveModel::Errors.new(Recipe.new)
    analysis_errors.add(:base, I18n.t("patient.recipes.errors.nutrition_analysis_unavailable"))
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
      images: [ uploaded_recipe_image ]
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
        images: [ uploaded_recipe_image ]
      )
    end.to raise_error(StandardError, "attach failed")

    expect(recipe.reload.name).to eq("Original name")
  end
end
