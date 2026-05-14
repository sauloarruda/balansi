FactoryBot.define do
  factory :meal do
    association :journal
    meal_type { "lunch" }
    description { "Chicken and rice" }
    status { "pending_llm" }
  end
end
