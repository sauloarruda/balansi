module JournalHelper
  def format_date(date)
    I18n.l(date, format: :long)
  end

  def format_status(status)
    case status
    when "pending_llm"
      "Pending AI"
    when "pending_patient"
      "Pending Review"
    when "confirmed"
      "Confirmed"
    else
      status.humanize
    end
  end

  def calculate_calories_consumed(meals)
    meals.select { |m| m[:status] == "confirmed" }.sum { |m| m[:calories] || 0 }
  end

  def calculate_calories_burned(exercises, bmr)
    exercise_calories = exercises.select { |e| e[:status] == "confirmed" }.sum { |e| e[:calories] || 0 }
    (bmr || 0) + exercise_calories
  end

  def calculate_balance(journal, patient)
    consumed = journal[:calories_consumed] || calculate_calories_consumed(journal[:meals])
    burned = journal[:calories_burned] || calculate_calories_burned(journal[:exercises], patient[:bmr])
    consumed - burned
  end

  def balance_class(journal, patient)
    balance = calculate_balance(journal, patient)
    if balance > 300
      "positive"
    elsif balance < -500
      "negative"
    else
      "balanced"
    end
  end

  def progress_percentage(consumed, goal)
    return 0 if goal.nil? || goal.zero?
    [(consumed.to_f / goal * 100).round, 100].min
  end

  def count_pending_entries(journal)
    pending_meals = journal[:meals].count { |m| m[:status] == "pending_llm" || m[:status] == "pending_patient" }
    pending_exercises = journal[:exercises].count { |e| e[:status] == "pending_llm" || e[:status] == "pending_patient" }
    pending_meals + pending_exercises
  end

  def journal_editable?(journal)
    return false unless journal[:closed_at]
    Date.current <= journal[:date] + 2.days
  end

  def score_color(score)
    case score
    when 1 then "red"
    when 2 then "orange"
    when 3 then "yellow"
    when 4 then "teal"
    when 5 then "green"
    else "gray"
    end
  end
end
