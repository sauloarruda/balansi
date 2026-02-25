class AddClinicalAssessmentLastUpdatedAtToPatients < ActiveRecord::Migration[8.1]
  def change
    add_column :patients, :clinical_assessment_last_updated_at, :datetime
  end
end
