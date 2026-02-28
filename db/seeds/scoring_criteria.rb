# Scoring criteria seed data for daily journal scoring
# These templates are used as the {scoring_criteria} variable in the LLM scoring prompt.
# In a future version, scoring criteria will be configurable per nutritionist per patient.
# For v1, a single default template is used for all patients.

JOURNAL_SCORING_CRITERIA_DEFAULT = <<~CRITERIA
  Balance caloric deficit with nutritional adequacy, exercise appropriateness, and sustainable habits.

  Scoring criteria:
  SCORE 5
  - Caloric balance: Within -200 and +100 kcal of daily goal (considering BMR + exercise)
  - Protein: Within adequate range for patient profile
  - 2 meals with fruit
  - 2 meals with vegetable servings
  - Exercise: Present today with appropriate intensity for patient profile
  - Meal quality: All meals nutritionally balanced (evaluate from descriptions and macros)
  - Sleep: Excellent quality (from user input)
  - Hydration: Excellent (from user input, meeting daily goal)
  - Steps: Meeting daily goal (from user input)
  - No candy

  SCORE 4
  - Caloric balance: Within -300 and +150 of goal
  - 1 meal with fruit
  - 2 meals with vegetable servings
  - Exercise present but may be slightly below target intensity/duration
  - Occasional processed foods detectable
  - Sleep: Good quality
  - Hydration: Good (close to daily goal)
  - Steps: Close to daily goal
  - No candy

  SCORE 3
  - Caloric balance: Within -500 and +300 kcal of goal
  - 1 meal with fruit
  - 1 meal with vegetable servings
  - Exercise missing or intensity/duration inappropriate for patient profile
  - Multiple processed food meals detectable
  - Sleep: Poor quality
  - Hydration: Poor (significantly below daily goal)
  - Steps: Below daily goal
  - Little candy allowed

  SCORE 2
  - Caloric balance: >500 kcal deficit OR >300 kcal surplus
  - Severe macro imbalances (e.g., protein too low, excessive carbs/fats)
  - <60% of fruit/vegetable servings
  - No exercise OR excessive exercise intensity
  - Excessive processed foods
  - Sleep: Poor quality
  - Hydration: Poor (well below daily goal)
  - Steps: Well below daily goal

  SCORE 1
  - Severe caloric restriction (<1200 kcal for women, <1500 for men) OR large surplus (>800 kcal)
  - Critical macro deficiencies
  - Minimal to no fruits/vegetables
  - No exercise OR dangerous exercise intensity
  - Sleep: Poor quality
  - Hydration: Very poor (minimal water intake)
  - Steps: Minimal or no steps

  EXERCISE INTENSITY GUARDRAILS:
  - Obese patients (BMI >30): Prefer light-moderate intensity. High intensity exercises should reduce score.
  - Normal/overweight: Moderate to high intensity acceptable based on fitness level.
  - If exercise intensity too high for patient profile -> reduce score by 1 point, warn in feedback.

  QUALITY OF LIFE PRIORITIES:
  1. Prevent extreme caloric restriction that may cause muscle loss, fatigue, or metabolic issues
  2. Ensure adequate protein to preserve muscle during weight loss
  3. Maintain variety and micronutrient intake (fruits/vegetables)
  4. Promote sustainable exercise habits appropriate to patient condition
  5. Avoid over-restriction that leads to binge eating or unsustainable patterns
  6. Encourage quality sleep and adequate hydration
  7. Promote daily movement (steps) appropriate to patient condition

  Note: Weekly context variables (alcohol, red meat, processed foods, etc.) should be considered as
  supporting information but not primary scoring factors. Evaluate daily performance primarily from
  today's data.
CRITERIA

puts "[scoring_criteria] Default scoring criteria template loaded."
