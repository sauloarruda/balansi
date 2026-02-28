class Journal::DailyScoringClient < Journal::BaseAnalysisClient
  def score(journal:, patient:, user_language: "pt")
    request_payload = build_request_payload(journal: journal, patient: patient, user_language: user_language)
    normalize_payload(perform_chat_completion(request_payload: request_payload))
  end

  private

  def build_request_payload(journal:, patient:, user_language:)
    {
      model: openai_model,
      temperature: 0.3,
      messages: [
        { role: "system", content: system_prompt(user_language) },
        { role: "user", content: user_prompt(journal: journal, patient: patient, user_language: user_language) }
      ]
    }
  end

  def normalize_payload(parsed)
    {
      s: parsed["s"],
      fp: parsed["fp"],
      fi: parsed["fi"]
    }
  end

  def system_prompt(user_language)
    if user_language.to_s.start_with?("pt")
      "Você é um nutricionista assistente. Avalie o diário diário e retorne apenas JSON válido, sem markdown."
    else
      "You are a nutrition assistant. Evaluate the daily journal and return only valid JSON, without markdown."
    end
  end

  def user_prompt(journal:, patient:, user_language:)
    ctx = journal.weekly_context
    confirmed_meals = journal.confirmed_meals.order(:created_at)
    confirmed_exercises = journal.confirmed_exercises.order(:created_at)

    meals_summary = confirmed_meals.map do |m|
      "#{m.meal_type}|#{m.calories}|#{m.proteins}|#{m.carbs}|#{m.fats}|#{m.description}"
    end.join("\n")

    exercises_summary = confirmed_exercises.map do |e|
      "#{e.duration}|#{e.calories}|#{e.structured_description || e.description}"
    end.join("\n")

    calories_consumed = journal.calculate_calories_consumed
    calories_burned = journal.calculate_calories_burned
    exercise_calories = journal.exercise_calories_burned
    balance = calories_consumed - calories_burned

    scoring_criteria = defined?(JOURNAL_SCORING_CRITERIA_DEFAULT) ? JOURNAL_SCORING_CRITERIA_DEFAULT : ""

    <<~PROMPT
      Evaluate daily journal and calculate score (1-5).

      Lang: #{user_language}
      Date: #{journal.date}

      Patient: goal=#{patient.daily_calorie_goal}kcal, BMR=#{patient.bmr}kcal
      Daily: consumed=#{calories_consumed}kcal, burned=#{calories_burned}kcal (BMR #{patient.bmr}+ex #{exercise_calories}), balance=#{balance}kcal
      Metrics: feeling=#{journal.feeling_today}, sleep=#{journal.sleep_quality}, hydration=#{journal.hydration_quality} (goal #{patient.hydration_goal}ml), steps=#{journal.steps_count} (goal #{patient.steps_goal})
      Note: #{journal.daily_note}

      Meals (#{confirmed_meals.size}):
      #{meals_summary.presence || "(none)"}

      Exercises (#{confirmed_exercises.size}):
      #{exercises_summary.presence || "(none)"}

      Week (day #{ctx[:day_of_week]} of 7, #{ctx[:days_with_entries]} days with entries):
      - Alcohol: #{ctx[:days_with_alcohol]}/#{ctx[:day_of_week]}, Red meat: #{ctx[:days_with_red_meat]}/#{ctx[:day_of_week]}, Candy: #{ctx[:days_with_candy]}/#{ctx[:day_of_week]}, Soda: #{ctx[:days_with_soda]}/#{ctx[:day_of_week]}
      - Protein goal: #{ctx[:days_meeting_protein]}/#{ctx[:day_of_week]}, Exercise: #{ctx[:days_with_exercise]}/#{ctx[:day_of_week]}, Steps goal: #{ctx[:days_meeting_steps]}/#{ctx[:day_of_week]}
      - Score <=3: #{ctx[:days_score_low]}/#{ctx[:day_of_week]}, Processed: #{ctx[:days_with_processed]}/#{ctx[:day_of_week]}
      - Quality sleep: #{ctx[:days_quality_sleep]}/#{ctx[:day_of_week]}, Hydration: #{ctx[:days_adequate_hydration]}/#{ctx[:day_of_week]}, Feeling bad: #{ctx[:days_feeling_bad]}/#{ctx[:day_of_week]}

      Criteria:
      #{scoring_criteria}

      Calculate score. Consider balance, macros, meal quality, exercise appropriateness, quality of life.

      Return JSON:
      {
        "s": <1-5>,
        "fp": "<what went well, 2-3 sentences, #{user_language}>",
        "fi": "<what to improve, 2-3 sentences, #{user_language}>"
      }
    PROMPT
  end
end
