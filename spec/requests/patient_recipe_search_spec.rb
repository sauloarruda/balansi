require "rails_helper"

RSpec.describe "Patient recipe search", type: :request do
  let(:user) { create(:user) }
  let!(:patient) { create(:patient, user: user) }

  before do
    host! "localhost"
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end

  it "returns picker data for matching recipes owned by the current patient" do
    recipe = create(
      :recipe,
      patient: patient,
      name: "Bolo de banana",
      calories: 320,
      proteins: 8.5,
      carbs: 48.25,
      fats: 10.75,
      portion_size_grams: 180
    )
    image = create(:image, recipe: recipe)
    create(:recipe, patient: patient, name: "Panqueca de aveia")
    other_recipe = create(:recipe, name: "Bolo privado")

    get search_patient_recipes_path, params: { q: "Bolo" }

    expect(response).to have_http_status(:ok)

    body = response.parsed_body
    expect(body).to contain_exactly(
      {
        "id" => recipe.id,
        "name" => "Bolo de banana",
        "thumbnail_url" => a_string_including("/rails/active_storage/representations/"),
        "calories_per_portion" => 320.0,
        "proteins_per_portion" => 8.5,
        "carbs_per_portion" => 48.25,
        "fats_per_portion" => 10.75,
        "portion_size_grams" => 180.0
      }
    )
    expect(body.to_json).not_to include(other_recipe.name)
    expect(image.file).to be_attached
  end

  it "returns picker data when the query matches the middle of a recipe name" do
    recipe = create(:recipe, patient: patient, name: "Carne com legumes")
    create(:recipe, patient: patient, name: "Carne assada")

    get search_patient_recipes_path, params: { q: "legumes" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck("id")).to eq([ recipe.id ])
  end

  it "limits matching recipes to ten results ordered by name" do
    11.times do |index|
      create(:recipe, patient: patient, name: "Bolo #{index.to_s.rjust(2, "0")}")
    end

    get search_patient_recipes_path, params: { q: "Bolo" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck("name")).to eq(
      10.times.map { |index| "Bolo #{index.to_s.rjust(2, "0")}" }
    )
  end

  it "returns an empty array when the query is blank" do
    create(:recipe, patient: patient, name: "Bolo de cenoura")

    get search_patient_recipes_path

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
  end

  it "returns five recent patient recipes when recent suggestions are requested" do
    6.times do |index|
      create(:recipe, patient: patient, name: "Receita #{index}", updated_at: index.minutes.from_now)
    end
    create(:recipe, name: "Receita privada", updated_at: 1.hour.from_now)

    get search_patient_recipes_path, params: { q: "", recent: "true" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck("name")).to eq(
      [ "Receita 5", "Receita 4", "Receita 3", "Receita 2", "Receita 1" ]
    )
  end
end
