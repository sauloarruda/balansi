FactoryBot.define do
  factory :journal do
    patient do
      ensure_fixtures_are_loaded
      Patient.find_by(id: 2001) || association(:patient)
    end
    date do
      Date.new(2026, 2, 5)
    end

    to_create do |instance|
      ensure_fixtures_are_loaded
      existing = Journal.find_by(patient_id: instance.patient_id, date: instance.date)
      if existing
        instance.id = existing.id
        instance.reload
      else
        instance.save!
      end
    end
  end
end
