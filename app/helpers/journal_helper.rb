module JournalHelper
  def format_date(date)
    I18n.l(date, format: :long)
  end

  def format_meal_description(description, recipe_references: [], link_recipes: true, patient_id: nil)
    return "" if description.blank?

    nodes = []
    text = description.to_s
    last_index = 0
    reference_by_recipe_id = meal_recipe_reference_by_recipe_id(recipe_references)
    portions_by_recipe_id = reference_by_recipe_id.empty? ? meal_recipe_portions_by_id(text) : {}

    text.to_enum(:scan, meal_recipe_mention_pattern).each do
      match = Regexp.last_match
      nodes.concat(meal_description_text_nodes(text[last_index...match.begin(0)]))
      nodes << meal_recipe_chip(
        match[:name],
        reference: reference_by_recipe_id[match[:id]],
        portion_size_grams: portions_by_recipe_id[match[:id]],
        link_recipe: link_recipes,
        patient_id:
      )
      last_index = match.end(0)
    end

    nodes.concat(meal_description_text_nodes(text[last_index..]))
    safe_join(nodes)
  end

  def meal_recipe_mention_data(description)
    recipe_mention_data(description)
  end

  def recipe_mention_data(description)
    recipe_ids = recipe_mention_ids(description)
    return [] if recipe_ids.empty?

    current_patient_recipes
      .where(id: recipe_ids)
      .pluck(:id, :portion_size_grams, :calories, :proteins, :carbs, :fats)
      .map do |id, portion_size_grams, calories, proteins, carbs, fats|
        {
          id: id,
          portion_size_grams: portion_size_grams.to_f,
          calories_per_portion: calories&.to_f,
          proteins_per_portion: proteins&.to_f,
          carbs_per_portion: carbs&.to_f,
          fats_per_portion: fats&.to_f
        }
      end
  end

  def recipe_mention_ids(description)
    description.to_s.scan(meal_recipe_mention_pattern).map { |_name, id| id.to_i }.uniq
  end

  def recipe_mentions_controller_data(initial_recipes)
    {
      controller: "character-counter recipe-mentions",
      "recipe-mentions-search-url-value": search_patient_recipes_path,
      "recipe-mentions-new-recipe-url-value": new_patient_recipe_path,
      "recipe-mentions-loading-text-value": t("meals.recipe_mentions.loading"),
      "recipe-mentions-no-results-text-value": t("meals.recipe_mentions.no_results"),
      "recipe-mentions-error-text-value": t("meals.recipe_mentions.error"),
      "recipe-mentions-create-recipe-text-value": t("meals.recipe_mentions.create_recipe"),
      "recipe-mentions-kcal-text-value": t("defaults.kcal"),
      "recipe-mentions-grams-text-value": t("defaults.grams"),
      "recipe-mentions-carbs-text-value": t("defaults.carbs"),
      "recipe-mentions-protein-text-value": t("defaults.protein"),
      "recipe-mentions-fats-text-value": t("defaults.fats"),
      "recipe-mentions-initial-recipes-value": initial_recipes.to_json,
      "recipe-mentions-reference-prefix-value": Recipe::MENTION_PREFIX,
      "recipe-mentions-reference-middle-value": Recipe::MENTION_MIDDLE,
      "recipe-mentions-reference-suffix-value": Recipe::MENTION_SUFFIX
    }
  end

  def format_recipe_reference_value(value)
    return "-" if value.blank?

    number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
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
      elsif pct < 100
        missing = goal - current.to_i
        "#{label}: #{current.to_i}g / #{goal}g (#{pct}%, #{missing}g #{t('defaults.missing')})"
      else
        "#{label}: #{current.to_i}g / #{goal}g (#{pct}%)"
      end
    else
      "#{label}: #{current.to_i}g"
    end
  end

  def meal_recipe_mention_pattern
    Recipe::MENTION_PATTERN
  end

  def meal_recipe_mention_ids(description)
    description.to_s.scan(meal_recipe_mention_pattern).map { |_name, id| id }.uniq
  end

  def meal_recipe_portions_by_id(description)
    recipe_ids = meal_recipe_mention_ids(description)
    return {} if recipe_ids.empty?

    current_patient_recipes
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

  def meal_recipe_reference_by_recipe_id(recipe_references)
    Array(recipe_references).each_with_object({}) do |reference, references_by_id|
      next if reference.recipe_id.blank?

      references_by_id[reference.recipe_id.to_s] ||= reference
    end
  end

  def meal_recipe_chip(name, reference: nil, portion_size_grams: nil, link_recipe: true, patient_id: nil)
    label = meal_recipe_chip_label(name, reference&.portion_size_grams || portion_size_grams)
    return tag.span(label, class: "recipe-mention-chip") if reference.blank?

    tag.span(class: "inline-flex", data: { controller: "popover-tooltip", popover_tooltip_placement: "top" }) do
      safe_join([
        tag.button(
          label,
          type: "button",
          class: "recipe-mention-chip",
          aria: { label: t("meals.recipe_references.open_details", recipe: name) }
        ),
        meal_recipe_tooltip(name, reference:, link_recipe:, patient_id:)
      ])
    end
  end

  def meal_recipe_tooltip(name, reference:, link_recipe: true, patient_id: nil)
    tag.div(
      class: "tooltip hidden opacity-0 transition-opacity duration-150 fixed z-50 rounded-lg bg-gray-900 p-3 text-left text-sm text-white shadow-lg w-max max-w-[calc(100vw-2rem)]",
      data: { popover_tooltip_target: "tip" },
      role: "tooltip"
    ) do
      safe_join([
        tag.div(class: "space-y-3") do
          safe_join([
            meal_recipe_tooltip_header(name, reference),
            meal_recipe_tooltip_nutrition(reference),
            meal_recipe_tooltip_link(reference, link_recipe:, patient_id:)
          ].compact)
        end,
        tag.div(class: "tooltip-arrow")
      ])
    end
  end

  def meal_recipe_tooltip_header(name, reference)
    recipe_deleted = reference.recipe.blank? || reference.recipe.discarded?

    tag.div(class: "flex items-start justify-between gap-3") do
      safe_join([
        tag.div(class: "min-w-0") do
          safe_join([
            tag.div(name, class: "font-semibold leading-5"),
            tag.div(
              t("meals.recipe_references.portion_size", grams: format_recipe_reference_value(reference.portion_size_grams)),
              class: "mt-0.5 text-xs text-gray-300"
            )
          ])
        end,
        (tag.span(t("meals.recipe_references.deleted_recipe"), class: "shrink-0 rounded-full bg-gray-700 px-2 py-0.5 text-xs text-gray-200") if recipe_deleted)
      ].compact)
    end
  end

  def meal_recipe_tooltip_nutrition(reference)
    tag.div(class: "flex items-center gap-3 rounded-base border border-pink-100 bg-pink-50 px-3 py-2 text-gray-900") do
      safe_join([
        tag.div(class: "shrink-0") do
          safe_join([
            tag.span(format_recipe_reference_value(reference.calories_per_portion), class: "text-body font-bold text-pink-900"),
            tag.span(t("defaults.kcal"), class: "text-xs text-pink-600 ml-0.5")
          ])
        end,
        tag.div(class: "shrink-0") do
          tag.span("#{format_recipe_reference_value(reference.portion_size_grams)}#{t("defaults.grams")}", class: "text-xs font-bold text-gray-500")
        end,
        render("shared/macro_circles", carbs: reference.carbs_per_portion.to_f, proteins: reference.proteins_per_portion.to_f, fats: reference.fats_per_portion.to_f, size: :sm, hide_labels_mobile: true)
      ])
    end
  end

  def meal_recipe_tooltip_link(reference, link_recipe: true, patient_id: nil)
    recipe = reference.recipe
    return unless link_recipe && recipe.present? && recipe.kept? && recipe.patient_id == patient_id

    link_to(
      t("meals.recipe_references.view_recipe"),
      patient_recipe_path(recipe),
      class: "inline-flex text-xs font-medium text-white underline underline-offset-2 hover:text-gray-200"
    )
  end

  def meal_recipe_chip_label(name, portion_size_grams)
    return name if portion_size_grams.blank?

    portion = number_with_precision(portion_size_grams, precision: 2, strip_insignificant_zeros: true)
    "#{name} (#{portion}g)"
  end

  def current_patient_recipes
    return Recipe.none unless respond_to?(:current_patient)

    current_patient&.recipes&.kept || Recipe.none
  end
end
