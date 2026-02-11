module JournalEntries
  module GenderedFlashMessages
    private

    def success_message_for(action:, model_key:, gender:)
      model_name = I18n.t("activerecord.models.#{model_key}.one", locale: current_user.language)

      I18n.t(
        "defaults.messages.#{action}_success.#{gender}",
        locale: current_user.language,
        model: model_name,
        default: I18n.t(
          "defaults.messages.#{action}_success.default",
          locale: current_user.language,
          model: model_name
        )
      )
    end
  end
end
