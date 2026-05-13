module JournalHelper
  def format_date(date)
    I18n.l(date, format: :long)
  end

  def format_meal_description(description, recipe_scope: nil)
    return "" if description.blank?

    nodes = []
    text = description.to_s
    last_index = 0
    portions_by_recipe_id = meal_recipe_portions_by_id(text, recipe_scope)

    text.to_enum(:scan, meal_recipe_mention_pattern).each do
      match = Regexp.last_match
      nodes.concat(meal_description_text_nodes(text[last_index...match.begin(0)]))
      nodes << meal_recipe_chip(match[:name], portions_by_recipe_id[match[:id]])
      last_index = match.end(0)
    end

    nodes.concat(meal_description_text_nodes(text[last_index..]))
    safe_join(nodes)
  end

  def meal_recipe_mention_data(description, recipe_scope:)
    recipe_ids = meal_recipe_mention_ids(description)
    return [] if recipe_ids.empty? || recipe_scope.nil?

    recipe_scope
      .where(id: recipe_ids)
      .pluck(:id, :portion_size_grams)
      .map do |id, portion_size_grams|
        {
          id: id,
          portion_size_grams: portion_size_grams.to_f
        }
      end
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
      balance_status == "negative" ? "below_goal" : "maintenance"
    elsif balance_percentage > 10
      "weight_gain"
    elsif balance_percentage < -20
      "below_goal"
    elsif balance_percentage < -10
      "weight_loss"
    else
      "maintenance"
    end
  end

  def balance_style_classes(balance_visual_status) # rubocop:disable Metrics/MethodLength
    case balance_visual_status
    when "weight_gain"
      {
        border: "border-red-500",
        bg: "from-red-50 to-red-100",
        text: "text-red-800",
        value: "text-red-900",
        unit: "text-red-700",
        message: "text-red-800"
      }
    when "weight_loss"
      {
        border: "border-green-500",
        bg: "from-green-50 to-green-100",
        text: "text-green-800",
        value: "text-green-900",
        unit: "text-green-700",
        message: "text-green-800"
      }
    when "below_goal"
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

  def balance_message_key(balance_visual_status, _balance_percentage = nil)
    case balance_visual_status
    when "weight_gain"
      ".weight_gain"
    when "below_goal"
      ".below_goal"
    when "weight_loss"
      ".weight_loss"
    else
      ".maintenance"
    end
  end

  def caloric_balance_visual_status(consumed_calories, burned_calories, calorie_goal)
    consumed = consumed_calories.to_f
    bounds = caloric_balance_bounds(burned_calories, calorie_goal)

    return "weight_gain" if consumed >= bounds[:burned_upper]
    return "below_goal" if below_goal_intake?(consumed, bounds[:goal_lower], calorie_goal)

    return classify_goal_aligned_intake(consumed, bounds) if goal_aligned_intake?(consumed, bounds)

    classify_by_expenditure_range(consumed, bounds)
  end

  private

  def caloric_balance_bounds(burned_calories, calorie_goal)
    burned = burned_calories.to_f
    goal = calorie_goal.to_f

    {
      goal_lower: goal * 0.90,
      goal_upper: goal * 1.10,
      burned_lower: burned * 0.85,
      burned_upper: burned * 1.15
    }
  end

  def below_goal_intake?(consumed, goal_lower_bound, calorie_goal)
    calorie_goal.to_f.positive? && consumed < goal_lower_bound
  end

  def goal_aligned_intake?(consumed, bounds)
    consumed >= bounds[:goal_lower] && consumed <= bounds[:goal_upper]
  end

  def classify_goal_aligned_intake(consumed, bounds)
    if consumed >= bounds[:burned_lower] && consumed <= bounds[:burned_upper]
      "maintenance"
    elsif consumed < bounds[:burned_lower]
      "weight_loss"
    else
      "weight_gain"
    end
  end

  def classify_by_expenditure_range(consumed, bounds)
    if consumed >= bounds[:burned_lower] && consumed <= bounds[:burned_upper]
      "maintenance"
    elsif consumed < bounds[:burned_lower]
      "weight_loss"
    else
      "weight_gain"
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

  def macro_goal_percentage(current, goal)
    return nil if goal.nil? || goal.zero?

    (current.to_f / goal * 100).round
  end

  def macro_goal_excess_percentage(current, goal)
    return nil if goal.nil? || goal.zero?

    raw = (current.to_f / goal * 100).round
    raw > 100 ? [ raw - 100, 100 ].min : nil
  end

  def macro_tooltip_text(current, goal, label)
    pct = macro_goal_percentage(current, goal)
    if pct.present?
      if pct > 100
        excess = current.to_i - goal
        "#{label}: #{current.to_i}g / #{goal}g (#{pct}%, +#{excess}g #{t('defaults.excess')})"
      else
        "#{label}: #{current.to_i}g / #{goal}g (#{pct}%)"
      end
    else
      "#{label}: #{current.to_i}g"
    end
  end

  def meal_recipe_mention_pattern
    /@\[ (?<name>[^\]]+) \]\(recipe:(?<id>\d+)\)/x
  end

  def meal_recipe_mention_ids(description)
    description.to_s.scan(meal_recipe_mention_pattern).map { |_name, id| id }.uniq
  end

  def meal_recipe_portions_by_id(description, recipe_scope)
    recipe_ids = meal_recipe_mention_ids(description)
    return {} if recipe_ids.empty? || recipe_scope.nil?

    recipe_scope
      .where(id: recipe_ids)
      .pluck(:id, :portion_size_grams)
      .to_h
      .transform_keys(&:to_s)
  end

  def meal_description_text_nodes(text)
    text.to_s.split("\n", -1).flat_map.with_index do |line, index|
      index.zero? ? [ line ] : [ tag.br, line ]
    end
  end

  def meal_recipe_chip(name, portion_size_grams = nil)
    tag.span(
      meal_recipe_chip_label(name, portion_size_grams),
      class: "recipe-mention-chip"
    )
  end

  def meal_recipe_chip_label(name, portion_size_grams)
    return name if portion_size_grams.blank?

    portion = number_with_precision(portion_size_grams, precision: 2, strip_insignificant_zeros: true)
    "#{name} (#{portion}g)"
  end
end
