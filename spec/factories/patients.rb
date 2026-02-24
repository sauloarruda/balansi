FactoryBot.define do
  factory :patient do
    association :user
    association :professional
    gender { "female" }
    birth_date { Date.new(1990, 1, 1) }
    weight_kg { 70.0 }
    height_cm { 170.0 }
    phone_e164 { "+5511999999999" }
    profile_completed_at { Time.current }
    profile_last_updated_at { profile_completed_at }

    trait :incomplete_profile do
      gender { nil }
      birth_date { nil }
      weight_kg { nil }
      height_cm { nil }
      phone_e164 { nil }
      profile_completed_at { nil }
      profile_last_updated_at { nil }
    end
  end
end
