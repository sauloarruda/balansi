module JournalEntries
  class MealsController < ApplicationController
    include JournalEntries::GenderedFlashMessages

    before_action :set_journal_date
    before_action :set_journal, only: [ :create ]
    before_action :set_meal, only: [ :show, :edit, :update, :destroy ]

    def new
      @meal = Meal.new(meal_type: params[:meal_type] || Meal::MEAL_TYPES.first)
    end

    def create
      @meal = @journal.meals.build(create_meal_params)
      @meal.status = :pending_llm

      unless @meal.save
        render :new, status: :unprocessable_entity
        return
      end

      if analyze_meal(@meal)
        flash[:notice] = success_message_for(action: :create, model_key: :meal, gender: :female)
      else
        flash[:error] = analysis_error_message
      end

      redirect_to journal_meal_path(journal_date: @journal.date.iso8601, id: @meal.id)
    end

    def show; end

    def edit; end

    def update
      if params[:reprocess].present?
        reprocess_meal
        return
      end

      if @meal.update(update_meal_params)
        @meal.confirm! if params[:confirm].present?

        flash[:notice] = success_message_for(action: :update, model_key: :meal, gender: :female)
        redirect_to journal_path(date: @meal.journal.date.iso8601)
      else
        template = params[:confirm].present? ? :show : :edit
        render template, status: :unprocessable_entity
      end
    end

    def destroy
      journal_date = @meal.journal.date.iso8601
      @meal.destroy!

      flash[:notice] = success_message_for(action: :delete, model_key: :meal, gender: :female)
      redirect_to journal_path(date: journal_date)
    end

    private

    def set_journal_date
      @journal_date = parse_date_param(meal_form_date_param) ||
        parse_date_param(params[:journal_date] || params[:journal_id]) ||
        Date.current
    end

    def set_journal
      @journal = current_patient.journals.find_or_create_by!(date: @journal_date)
    end

    def set_meal
      @meal = Meal.joins(:journal)
        .includes(:journal)
        .find_by(id: params[:id], journals: { patient_id: current_patient.id })

      return if @meal

      head :not_found
    end

    def reprocess_meal
      previous_status = @meal.status

      if @meal.update(reprocess_meal_params)
        @meal.update!(status: :pending_llm)

        if analyze_meal(@meal, previous_status: previous_status)
          flash[:notice] = success_message_for(action: :reprocess, model_key: :meal, gender: :female)
        else
          flash[:error] = analysis_error_message
        end

        redirect_to journal_meal_path(journal_date: @meal.journal.date.iso8601, id: @meal.id)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def analyze_meal(meal, previous_status: nil)
      result = Journal::AnalyzeMealInteraction.run(
        meal: meal,
        user_id: current_user.id,
        description: meal.description,
        meal_type: meal.meal_type,
        user_language: current_user.language
      )

      @analysis_errors = result.errors
      if result.valid?
        true
      else
        meal.update!(status: previous_status) if previous_status.present?
        false
      end
    end

    def analysis_error_message
      @analysis_errors&.full_messages&.to_sentence.presence ||
        I18n.t("journal.errors.llm_unavailable", locale: current_user.language)
    end

    def parse_date_param(raw_date)
      return nil if raw_date.blank?

      Date.iso8601(raw_date)
    rescue ArgumentError
      nil
    end

    def meal_form_date_param
      params.dig(:meal, :date)
    end

    def create_meal_params
      params.require(:meal).permit(:meal_type, :description)
    end

    def update_meal_params
      params.require(:meal).permit(
        :meal_type,
        :description,
        :calories,
        :proteins,
        :carbs,
        :fats,
        :gram_weight
      )
    end

    def reprocess_meal_params
      params.require(:meal).permit(:meal_type, :description)
    end
  end
end
