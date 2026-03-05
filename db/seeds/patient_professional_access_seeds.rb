# db/seeds/patient_professional_access_seeds.rb
# Seeds for testing patient data sharing with professionals

# Cria profissionais
professionals = []
5.times do |i|
  email = "professional#{i+1}@example.com"
  user = User.find_by(email: email)
  unless user
    user = User.create!(
      email: email,
      cognito_id: "cognito_professional_#{i+1}",
      name: "Professional #{i+1}",
      timezone: "America/Sao_Paulo",
      language: "pt"
    )
  end
  professional = Professional.find_by(user: user)
  unless professional
    professional = Professional.create!(user: user)
  end
  professionals << professional
  professionals << professional
end

# Cria pacientes
patients = []
5.times do |i|
  email = "patient#{i+1}@example.com"
  user = User.find_by(email: email)
  unless user
    user = User.create!(
      email: email,
      cognito_id: "cognito_patient_#{i+1}",
      name: "Patient #{i+1}",
      timezone: "America/Sao_Paulo",
      language: "pt"
    )
  end
  patient = Patient.find_by(user: user) || Patient.create!(user: user, professional: professionals.sample)
  patients << patient
end

# Compartilha dados de pacientes com profissionais
patients.each do |patient|
  # Each patient shares with 2 professionals
  professionals.sample(2).each do |professional|
    PatientProfessionalAccess.find_or_create_by!(patient: patient, professional: professional, granted_by_patient_user: patient.user)
  end
end

# Revoke access for some professionals
## No 'active' attribute to revoke access; skipping this step

puts "Patient-professional data sharing seeds created successfully."
