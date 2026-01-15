FactoryBot.define do
  factory :patient do
    association :user
    sequence(:professional_id) { |n| n }
  end
end
