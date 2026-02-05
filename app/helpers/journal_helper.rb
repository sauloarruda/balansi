module JournalHelper
  def format_date(date)
    I18n.l(date, format: :long)
  end

  def progress_percentage(consumed, goal)
    return 0 if goal.nil? || goal.zero?
    [(consumed.to_f / goal * 100).round, 100].min
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
