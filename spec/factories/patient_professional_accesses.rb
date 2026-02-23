FactoryBot.define do
  factory :patient_professional_access do
    association :patient
    association :professional
    association :granted_by_patient_user, factory: :user
  end
end
