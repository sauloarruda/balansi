module JournalHelper
  def format_date(date)
    I18n.l(date, format: :long)
  end

  def progress_percentage(consumed, goal)
    return 0 if goal.nil? || goal.zero?
    [(consumed.to_f / goal * 100).round, 100].min
  end
end
