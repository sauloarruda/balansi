class ApplicationFormBuilder < ActionView::Helpers::FormBuilder
  DEFAULT_LABEL_CLASSES = "block mb-2 text-sm font-medium text-gray-900".freeze
  DEFAULT_FIELD_CLASSES = "bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5".freeze
  SUBMIT_BASE_CLASSES = "inline-flex items-center justify-center box-border border border-transparent focus:ring-4 shadow-xs focus:outline-none cursor-pointer".freeze
  SUBMIT_SIZE_CLASSES = {
    sm: "font-medium rounded-base text-sm px-5 py-2.5",
    md: "font-medium rounded-lg text-base px-5 py-2.5",
    lg: "font-bold rounded-lg text-lg px-8 py-3"
  }.freeze
  SUBMIT_TONE_CLASSES = {
    blue: "text-white bg-blue-600 hover:bg-blue-700 focus:ring-blue-300",
    pink: "text-white bg-pink-600 hover:bg-pink-700 focus:ring-pink-300",
    sky: "text-white bg-sky-600 hover:bg-sky-700 focus:ring-sky-300",
    gray: "text-gray-700 bg-gray-200 hover:bg-gray-300 focus:ring-gray-300"
  }.freeze
  ERROR_INPUT_CLASSES = "border-red-500 focus:border-red-500 focus:ring-red-300".freeze
  ERROR_TEXT_CLASSES = "mt-2 text-sm text-red-600".freeze

  INPUT_HELPERS = %i[
    color_field
    date_field
    datetime_field
    email_field
    month_field
    number_field
    password_field
    search_field
    telephone_field
    text_field
    time_field
    url_field
    week_field
  ].freeze

  INPUT_HELPERS.each do |helper_name|
    define_method(helper_name) do |method, options = {}|
      options = with_field_state(method, options || {})
      append_error_message(method, super(method, options))
    end
  end

  def text_area(method, options = {})
    options = with_field_state(method, options || {})
    append_error_message(method, super(method, options))
  end

  def select(method, choices = nil, options = {}, html_options = {}, &block)
    html_options = with_field_state(method, html_options || {})
    append_error_message(method, super(method, choices, options, html_options, &block))
  end

  def collection_select(method, collection, value_method, text_method, options = {}, html_options = {})
    html_options = with_field_state(method, html_options || {})
    append_error_message(method, super(method, collection, value_method, text_method, options, html_options))
  end

  def label(method, text = nil, options = {}, &block)
    options = with_default_classes(options || {}, DEFAULT_LABEL_CLASSES)
    super(method, text, options, &block)
  end

  def submit(value = nil, options = {})
    normalized_options = options ? options.dup : {}
    return super(value, normalized_options) if normalized_options.delete(:unstyled)

    tone = normalized_options.delete(:tone)&.to_sym || :blue
    size = normalized_options.delete(:size)&.to_sym || :sm
    submit_classes = [
      SUBMIT_BASE_CLASSES,
      SUBMIT_SIZE_CLASSES.fetch(size, SUBMIT_SIZE_CLASSES[:sm]),
      SUBMIT_TONE_CLASSES.fetch(tone, SUBMIT_TONE_CLASSES[:blue])
    ].join(" ")

    normalized_options[:class] = merge_classes(normalized_options[:class], submit_classes)
    super(value, normalized_options)
  end

  private

  def with_field_state(method, options)
    styled_options = with_default_classes(options, DEFAULT_FIELD_CLASSES)
    with_error_state(method, styled_options)
  end

  def with_default_classes(options, default_classes)
    normalized_options = options.dup
    return normalized_options if normalized_options.delete(:unstyled)

    normalized_options.merge(class: merge_classes(normalized_options[:class], default_classes))
  end

  def with_error_state(method, options)
    return options unless field_has_errors?(method)

    classes = merge_classes(options[:class], ERROR_INPUT_CLASSES)
    options.merge(
      class: classes,
      "aria-invalid": true,
      "aria-describedby": error_element_id(method)
    )
  end

  def append_error_message(method, field_html)
    messages = field_error_messages(method)
    return field_html if messages.empty?

    message_html = @template.content_tag(
      :p,
      messages.first,
      id: error_element_id(method),
      class: ERROR_TEXT_CLASSES
    )

    @template.safe_join([ field_html, message_html ])
  end

  def field_has_errors?(method)
    field_error_messages(method).present?
  end

  def field_error_messages(method)
    return [] unless object&.respond_to?(:errors)

    Array(object.errors[method])
  end

  def error_element_id(method)
    "#{object_name}_#{method}_error"
  end

  def merge_classes(existing_classes, added_classes)
    [ existing_classes, added_classes ].compact.join(" ").squish
  end
end
