FactoryBot.define do
  factory :user do
    name { "Test User" }
    sequence(:email) { |n| "test#{n}@example.com" }
    sequence(:cognito_id) { |n| "cognito_user_#{n}" }
    timezone { "America/Sao_Paulo" }
    language { "pt" }
  end
end
