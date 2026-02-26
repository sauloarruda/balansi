require "rails_helper"

RSpec.describe Professionals::Patients::ClinicalAssessments::UpdateInteraction, type: :interaction do
  include ActiveSupport::Testing::TimeHelpers

  let(:professional) { create(:professional) }
  let(:patient) { create(:patient, professional: professional) }

  def assessment_params(attrs)
    attrs.stringify_keys
  end

  it "updates clinical assessment and clinical_assessment_last_updated_at when professional is owner" do
    result = nil
    travel_to(Time.zone.local(2026, 3, 1, 10, 0, 0)) do
      result = described_class.run(
        patient: patient,
        professional: professional,
        assessment_params: assessment_params(
          daily_calorie_goal: 2200,
          bmr: 1650,
          steps_goal: 8000,
          hydration_goal: 2500
        )
      )
    end

    expect(result.result).to eq(patient)

    patient.reload
    expect(patient.daily_calorie_goal).to eq(2200)
    expect(patient.bmr).to eq(1650)
    expect(patient.steps_goal).to eq(8000)
    expect(patient.hydration_goal).to eq(2500)
    expect(patient.clinical_assessment_last_updated_at).to eq(Time.zone.local(2026, 3, 1, 10, 0, 0))
  end

  it "returns nil when professional is not owner" do
    other_professional = create(:professional)
    other_patient = create(:patient, professional: other_professional)

    result = described_class.run(
      patient: other_patient,
      professional: professional,
      assessment_params: assessment_params(daily_calorie_goal: 2000)
    )

    expect(result.result).to be_nil
    expect(other_patient.reload.daily_calorie_goal).not_to eq(2000)
  end
end
