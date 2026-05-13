require "rails_helper"

RSpec.describe Recipes::AnalyzeNutritionInteraction, type: :interaction do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, language: "pt") }
  let(:patient) { create(:patient, user: user) }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
  end

  describe ".run" do
    it "updates missing nutrition values from analysis" do
      recipe = create(:recipe, patient: patient, calories: nil, proteins: nil, carbs: nil, fats: nil)
      client = instance_double(Recipes::NutritionAnalysisClient)
      allow(client).to receive(:analyze).and_return(
        {
          calories: 412.6,
          proteins: 24.125,
          carbs: 52.254,
          fats: 10.756
        }
      )
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(recipe: recipe, user_id: user.id, user_language: user.language)

      expect(result).to be_valid
      expect(recipe.reload.calories).to eq(413)
      expect(recipe.proteins).to eq(24.13)
      expect(recipe.carbs).to eq(52.25)
      expect(recipe.fats).to eq(10.76)
    end

    it "skips analysis when all nutrition values were provided manually" do
      recipe = create(:recipe, patient: patient)
      client = instance_double(Recipes::NutritionAnalysisClient)
      allow(client).to receive(:analyze)
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(recipe: recipe, user_id: user.id, user_language: user.language)

      expect(result).to be_valid
      expect(client).not_to have_received(:analyze)
    end

    it "assigns values without saving when persist is false" do
      recipe = create(:recipe, patient: patient, calories: nil, proteins: nil, carbs: nil, fats: nil)
      client = instance_double(Recipes::NutritionAnalysisClient)
      allow(client).to receive(:analyze).and_return(
        {
          calories: 390,
          proteins: 22,
          carbs: 48,
          fats: 9
        }
      )
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)

      result = described_class.run(recipe: recipe, user_id: user.id, user_language: user.language, persist: false)

      expect(result).to be_valid
      expect(recipe.calories).to eq(390)
      expect(recipe.reload.calories).to be_nil
    end

    it "fails when response is malformed without changing the recipe" do
      recipe = create(:recipe, patient: patient, calories: nil, proteins: nil, carbs: nil, fats: nil)
      client = instance_double(Recipes::NutritionAnalysisClient)
      allow(client).to receive(:analyze).and_return({ calories: 300 })
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)
      allow(Sentry).to receive(:capture_message)

      result = described_class.run(recipe: recipe, user_id: user.id, user_language: user.language)

      expect(result).not_to be_valid
      expect(result.errors.full_messages.to_sentence).to include("Não foi possível analisar esta receita agora")
      expect(recipe.reload.calories).to be_nil
      expect(Sentry).to have_received(:capture_message).with(
        "Recipe nutrition analysis invalid LLM response",
        hash_including(level: :error, tags: hash_including(recipe_id: recipe.id, user_id: user.id))
      )
    end

    it "reports unexpected errors without changing the recipe" do
      recipe = create(:recipe, patient: patient, calories: nil, proteins: nil, carbs: nil, fats: nil)
      client = instance_double(Recipes::NutritionAnalysisClient)
      allow(client).to receive(:analyze).and_raise(StandardError, "boom")
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)
      allow(Sentry).to receive(:capture_exception)

      result = described_class.run(recipe: recipe, user_id: user.id, user_language: user.language)

      expect(result).not_to be_valid
      expect(recipe.reload.calories).to be_nil
      expect(Sentry).to have_received(:capture_exception).with(
        an_instance_of(StandardError),
        hash_including(tags: hash_including(recipe_id: recipe.id, user_id: user.id, reason: "unexpected_error"))
      )
    end

    it "retries transient failures up to success" do
      recipe = create(:recipe, patient: patient, calories: nil, proteins: nil, carbs: nil, fats: nil)
      client = instance_double(Recipes::NutritionAnalysisClient)
      call_count = 0
      allow(client).to receive(:analyze) do
        call_count += 1
        raise Recipes::NutritionAnalysisClient::TransientError, "temporary" if call_count < 3

        {
          calories: 350,
          proteins: 21,
          carbs: 44,
          fats: 8
        }
      end
      allow_any_instance_of(described_class).to receive(:llm_client).and_return(client)
      allow_any_instance_of(described_class).to receive(:sleep)

      result = described_class.run(recipe: recipe, user_id: user.id, user_language: user.language)

      expect(result).to be_valid
      expect(call_count).to eq(3)
      expect(recipe.reload.calories).to eq(350)
    end

    it "blocks when hourly rate limit is exceeded" do
      travel_to(Time.zone.local(2026, 2, 5, 10, 0, 0)) do
        recipe = create(:recipe, patient: patient, calories: nil, proteins: nil, carbs: nil, fats: nil)
        hourly_key = "journal:llm:user:#{user.id}:hour:2026020510"
        cache_store.write(hourly_key, 10)

        result = described_class.run(recipe: recipe, user_id: user.id, user_language: user.language)

        expect(result).not_to be_valid
        expect(result.errors.full_messages.to_sentence).to include("Você excedeu seu limite de uso de IA")
      end
    end
  end
end
