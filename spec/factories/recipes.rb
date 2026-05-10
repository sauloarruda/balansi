FactoryBot.define do
  factory :recipe do
    association :patient
    name { "Chicken bowl" }
    ingredients { "Chicken breast, rice, beans, lettuce, tomato" }
    instructions { "Grill the chicken and serve it with rice, beans, lettuce, and tomato." }
    yield_portions { 2 }
    calories { 800 }
    proteins { 60 }
    carbs { 90 }
    fats { 24 }
  end
end
