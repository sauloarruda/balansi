module ApplicationHelper
  include HeroiconHelper
  include ActionView::Helpers::NumberHelper

  def localized_decimal(value, precision: 1)
    return "—" unless value.present?

    number_with_precision(value, precision: precision, strip_insignificant_zeros: true)
  end
end
