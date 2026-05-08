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
          hydration_goal: 2500,
          daily_carbs_goal: 250,
          daily_proteins_goal: 150,
          daily_fats_goal: 70
        )
      )
    end

    expect(result.result).to eq(patient)

    patient.reload
    expect(patient.daily_calorie_goal).to eq(2200)
    expect(patient.bmr).to eq(1650)
    expect(patient.steps_goal).to eq(8000)
    expect(patient.hydration_goal).to eq(2500)
    expect(patient.daily_carbs_goal).to eq(250)
    expect(patient.daily_proteins_goal).to eq(150)
    expect(patient.daily_fats_goal).to eq(70)
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

  it "updates clinical assessment when professional user is admin" do
    admin_user = create(:user, admin: true)
    admin_professional = create(:professional, user: admin_user)
    other_patient = create(:patient)

    result = described_class.run(
      patient: other_patient,
      professional: admin_professional,
      assessment_params: assessment_params(daily_calorie_goal: 2000)
    )

    expect(result.result).to eq(other_patient)
    expect(other_patient.reload.daily_calorie_goal).to eq(2000)
  end
end
