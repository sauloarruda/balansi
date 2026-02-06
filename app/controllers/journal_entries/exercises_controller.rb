module JournalEntries
  class ExercisesController < ApplicationController
    include JournalEntries::GenderedFlashMessages

    before_action :set_journal_date
    before_action :set_journal, only: [ :create ]
    before_action :set_exercise, only: [ :show, :edit, :update, :destroy ]

    def new
      @exercise = Exercise.new
    end

    def create
      @exercise = @journal.exercises.build(create_exercise_params)
      @exercise.status = :pending_llm

      unless @exercise.save
        render :new, status: :unprocessable_entity
        return
      end

      if analyze_exercise(@exercise)
        flash[:notice] = success_message_for(action: :create, model_key: :exercise, gender: :male)
      else
        flash[:error] = analysis_error_message
      end

      redirect_to journal_exercise_path(journal_date: @journal.date.iso8601, id: @exercise.id)
    end

    def show; end

    def edit; end

    def update
      if params[:reprocess].present?
        reprocess_exercise
        return
      end

      if @exercise.update(update_exercise_params)
        @exercise.confirm! if params[:confirm].present?

        flash[:notice] = success_message_for(action: :update, model_key: :exercise, gender: :male)
        redirect_to journal_path(date: @exercise.journal.date.iso8601)
      else
        template = params[:confirm].present? ? :show : :edit
        render template, status: :unprocessable_entity
      end
    end

    def destroy
      journal_date = @exercise.journal.date.iso8601
      @exercise.destroy!

      flash[:notice] = success_message_for(action: :delete, model_key: :exercise, gender: :male)
      redirect_to journal_path(date: journal_date)
    end

    private

    def set_journal_date
      @journal_date = parse_date_param(exercise_form_date_param) ||
        parse_date_param(params[:journal_date] || params[:journal_id]) ||
        Date.current
    end

    def set_journal
      @journal = current_patient.journals.find_or_create_by!(date: @journal_date)
    end

    def set_exercise
      @exercise = Exercise.joins(:journal)
        .includes(:journal)
        .find_by(id: params[:id], journals: { patient_id: current_patient.id })

      return if @exercise

      head :not_found
    end

    def reprocess_exercise
      previous_status = @exercise.status

      if @exercise.update(reprocess_exercise_params)
        @exercise.update!(status: :pending_llm)

        if analyze_exercise(@exercise, previous_status: previous_status)
          flash[:notice] = success_message_for(action: :reprocess, model_key: :exercise, gender: :male)
        else
          flash[:error] = analysis_error_message
        end

        redirect_to journal_exercise_path(journal_date: @exercise.journal.date.iso8601, id: @exercise.id)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def analyze_exercise(exercise, previous_status: nil)
      result = Journal::AnalyzeExerciseInteraction.run(
        exercise: exercise,
        user_id: current_user.id,
        description: exercise.description,
        user_language: current_user.language
      )

      @analysis_errors = result.errors
      if result.valid?
        true
      else
        exercise.update!(status: previous_status) if previous_status.present?
        false
      end
    end

    def analysis_error_message
      @analysis_errors&.full_messages&.to_sentence.presence ||
        I18n.t("journal.errors.exercise_llm_unavailable", locale: current_user.language)
    end

    def parse_date_param(raw_date)
      return nil if raw_date.blank?

      Date.iso8601(raw_date)
    rescue ArgumentError
      nil
    end

    def exercise_form_date_param
      params.dig(:exercise, :date)
    end

    def create_exercise_params
      params.require(:exercise).permit(:description)
    end

    def update_exercise_params
      params.require(:exercise).permit(
        :description,
        :duration,
        :calories,
        :neat,
        :structured_description
      )
    end

    def reprocess_exercise_params
      params.require(:exercise).permit(:description)
    end
  end
end
