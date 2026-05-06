module JournalHelper
  def format_date(date)
    I18n.l(date, format: :long)
  end

  def progress_percentage(consumed, goal)
    return 0 if goal.nil? || goal.zero?
    [ (consumed.to_f / goal * 100).round, 100 ].min
  end

  def balance_percentage(balance, calorie_goal)
    return nil unless calorie_goal.to_f.positive?

    (balance.to_f / calorie_goal.to_f) * 100
  end

  def balance_visual_status(balance_percentage, balance_status)
    if balance_percentage.nil?
      balance_status == "negative" ? "low_severe" : "balanced"
    elsif balance_percentage > 10
      "positive"
    elsif balance_percentage < -20
      "low_severe"
    elsif balance_percentage < -10
      "low_moderate"
    else
      "balanced"
    end
  end

  def balance_style_classes(balance_visual_status) # rubocop:disable Metrics/MethodLength
    case balance_visual_status
    when "positive"
      {
        border: "border-red-500",
        bg: "from-red-50 to-red-100",
        text: "text-red-800",
        value: "text-red-900",
        unit: "text-red-700",
        message: "text-red-800"
      }
    when "low_moderate"
      {
        border: "border-green-500",
        bg: "from-green-50 to-green-100",
        text: "text-green-800",
        value: "text-green-900",
        unit: "text-green-700",
        message: "text-green-800"
      }
    when "low_severe"
      {
        border: "border-orange-500",
        bg: "from-orange-50 to-orange-100",
        text: "text-orange-800",
        value: "text-orange-900",
        unit: "text-orange-700",
        message: "text-orange-800"
      }
    else
      {
        border: "border-blue-500",
        bg: "from-blue-50 to-blue-100",
        text: "text-blue-800",
        value: "text-blue-900",
        unit: "text-blue-700",
        message: "text-blue-800"
      }
    end
  end

  def balance_message_key(balance_visual_status, balance_percentage)
    return ".far_below_goal" if balance_visual_status == "low_severe" && balance_percentage && balance_percentage < -25

    case balance_visual_status
    when "positive"
      ".above_goal"
    when "low_moderate", "low_severe"
      ".below_goal"
    else
      ".balanced"
    end
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
