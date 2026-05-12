FactoryBot.define do
  factory :recipe do
    association :patient
    name { "Chicken bowl" }
    ingredients { "Chicken breast, rice, beans, lettuce, tomato" }
    instructions { "Grill the chicken and serve it with rice, beans, lettuce, and tomato." }
    portion_size_grams { 200 }
    calories { 400 }
    proteins { 30.25 }
    carbs { 45.12 }
    fats { 12.38 }
  end
end
