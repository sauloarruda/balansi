FactoryBot.define do
  factory :user do
    name { "Test User" }
    sequence(:email) { |n| "test#{n}@example.com" }
    timezone { "America/Sao_Paulo" }
    language { "pt" }

    trait :with_password do
      transient do
        password { "password123" }
      end

      after(:build) do |user, evaluator|
        user.password = evaluator.password
      end
    end
  end
end
