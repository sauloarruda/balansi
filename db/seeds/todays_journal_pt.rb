# Journal phase 2 seed
# Requirements:
# - Idempotent
# - Reuses an existing patient
# - Creates today's data in pt-BR

patient = Patient.order(:id).first

unless patient
  puts "[todays_journal_pt] No patient found. Journal seed skipped."
  return
end

journal_date = Time.zone.today

journal = Journal.find_or_create_by!(patient: patient, date: journal_date) do |j|
  j.closed_at = nil
end

# Cleanup legacy seed variants to keep this seed idempotent
legacy_meal_descriptions = [
  "Pao integral com ovo mexido e cafe sem acucar",
  "Arroz, feijao, frango grelhado e salada"
]
journal.meals.where(description: legacy_meal_descriptions).delete_all

meals_data = [
  {
    meal_type: "breakfast",
    description: "Pão integral com ovo mexido e café sem açúcar",
    proteins: 18,
    carbs: 32,
    fats: 12,
    calories: 320,
    gram_weight: 220,
    ai_comment: "Café da manhã equilibrado com boa fonte de proteína.",
    feeling: 1,
    status: "confirmed"
  },
  {
    meal_type: "lunch",
    description: "Arroz, feijão, frango grelhado e salada",
    proteins: 36,
    carbs: 48,
    fats: 14,
    calories: 520,
    gram_weight: 420,
    ai_comment: "Almoço completo com boa distribuição de macronutrientes.",
    feeling: 1,
    status: "confirmed"
  },
  {
    meal_type: "dinner",
    description: "Iogurte com banana e granola",
    proteins: 12,
    carbs: 34,
    fats: 8,
    calories: 260,
    gram_weight: 250,
    ai_comment: "Jantar leve, aguardando revisão do paciente.",
    feeling: 1,
    status: "pending_patient"
  }
]

meals_data.each do |attrs|
  meal = journal.meals.find_or_initialize_by(
    meal_type: attrs[:meal_type],
    description: attrs[:description]
  )
  meal.assign_attributes(attrs)
  meal.save!
end

exercises_data = [
  {
    description: "Caminhada moderada de 40 minutos",
    duration: 40,
    calories: 220,
    neat: 0,
    structured_description: "Caminhada moderada 40 min",
    status: "confirmed"
  },
  {
    description: "Alongamento e mobilidade por 20 minutos",
    duration: 20,
    calories: 60,
    neat: 0,
    structured_description: "Alongamento 20 min",
    status: "pending_patient"
  }
]

exercises_data.each do |attrs|
  exercise = journal.exercises.find_or_initialize_by(description: attrs[:description])
  exercise.assign_attributes(attrs)
  exercise.save!
end

puts "[todays_journal_pt] Seed applied for patient=#{patient.id} on #{journal_date}."
