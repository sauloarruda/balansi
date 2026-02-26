require "rails_helper"

RSpec.describe Auth::SignUpInteraction, type: :interaction do
  let(:valid_code) { "valid_auth_code_123" }
  let(:valid_state) { "professional_id=1" }
  let!(:default_professional) { Professional.find_by(id: 1) || create(:professional, id: 1) }

  describe ".run" do
    context "on success" do
      include_context "cognito stubs"

      it "creates user and patient record" do
        result = described_class.run(
          code: valid_code,
          state: valid_state,
          timezone: "America/Sao_Paulo",
          language: "pt"
        )

        expect(result).to be_valid
        expect(result.result).not_to be_nil
        expect(result.result[:user]).not_to be_nil
        expect(result.result[:refresh_token]).to eq("refresh_token_123")
        expect(result.result[:user]).to be_persisted
        expect(result.result[:user].email).to eq("test@example.com")
        expect(result.result[:user].cognito_id).to eq("cognito_stub_fixed_sub")
        expect(result.result[:user].patient).to be_present
      end

      it "finds existing user by cognito_id" do
        existing_user = create(:user, cognito_id: "cognito_stub_fixed_sub")

        result = described_class.run(
          code: valid_code,
          state: valid_state
        )

        expect(result).to be_valid
        expect(result.result[:user].id).to eq(existing_user.id)
      end

      it "creates patient record with professional_id from state" do
        Professional.find_by(id: 42) || create(:professional, id: 42)

        result = described_class.run(
          code: valid_code,
          state: "professional_id=42"
        )

        expect(result).to be_valid
        patient = result.result[:user].patient
        expect(patient).not_to be_nil
        expect(patient.professional_id).to eq(42)
      end

      it "allows authentication without state when patient already exists" do
        existing_cognito_id = "existing_patient_user_#{SecureRandom.hex(4)}"
        existing_user = create(:user, cognito_id: existing_cognito_id)
        existing_patient = create(:patient, user: existing_user, professional: default_professional)
        allow(CognitoService).to receive(:decode_id_token).and_return(valid_user_info.merge("sub" => existing_cognito_id))

        result = described_class.run(
          code: valid_code,
          state: nil
        )

        expect(result).to be_valid
        expect(result.result[:user].id).to eq(existing_user.id)
        expect(result.result[:user].patient.id).to eq(existing_patient.id)
        expect(result.result[:user].patient.professional_id).to eq(default_professional.id)
      end

      it "associates new users without state to the first professional" do
        result = described_class.run(
          code: valid_code,
          state: nil
        )

        expect(result).to be_valid
        expect(result.result[:user].patient).to be_present
        expect(result.result[:user].patient.professional_id).to eq(default_professional.id)
      end

      it "uses default timezone and language when not provided" do
        result = described_class.run(
          code: valid_code,
          state: valid_state
        )

        expect(result).to be_valid
        expect(result.result[:user].timezone).to eq("America/Sao_Paulo")
        expect(result.result[:user].language).to eq("pt")
      end

      it "parses professional_id from state parameter correctly" do
        Professional.find_by(id: 99) || create(:professional, id: 99)
        state = URI.encode_www_form("professional_id" => "99")
        result = described_class.run(
          code: valid_code,
          state: state
        )

        expect(result).to be_valid
        expect(result.result[:user].patient.professional_id).to eq(99)
      end

      it "does not update timezone and language for existing user" do
        existing_user = create(:user,
          cognito_id: "cognito_stub_fixed_sub",
          timezone: "America/New_York",
          language: "en")

        result = described_class.run(
          code: valid_code,
          state: valid_state,
          timezone: "America/Sao_Paulo",
          language: "pt"
        )

        expect(result).to be_valid
        expect(result.result[:user].timezone).to eq("America/New_York")
        expect(result.result[:user].language).to eq("en")
      end

      it "uses name when present in decoded token" do
        user_info_with_name = {
          "sub" => "cognito_stub_fixed_sub",
          "email" => "test@example.com",
          "name" => "Full Name"
        }
        allow(CognitoService).to receive(:decode_id_token).and_return(user_info_with_name)

        result = described_class.run(
          code: valid_code,
          state: valid_state
        )

        expect(result).to be_valid
        expect(result.result[:user].name).to eq("Full Name")
      end

      it "uses given_name when name is not present" do
        user_info_with_given_name = {
          "sub" => "cognito_stub_fixed_sub",
          "email" => "test@example.com",
          "given_name" => "Given Name"
        }
        allow(CognitoService).to receive(:decode_id_token).and_return(user_info_with_given_name)

        result = described_class.run(
          code: valid_code,
          state: valid_state
        )

        expect(result).to be_valid
        expect(result.result[:user].name).to eq("Given Name")
      end

      it "uses email as name when name and given_name are not present" do
        user_info_email_only = {
          "sub" => "cognito_stub_fixed_sub",
          "email" => "test@example.com"
        }
        allow(CognitoService).to receive(:decode_id_token).and_return(user_info_email_only)

        result = described_class.run(
          code: valid_code,
          state: valid_state
        )

        expect(result).to be_valid
        expect(result.result[:user].name).to eq("test@example.com")
      end

      it "uses userinfo endpoint when ID token decode fails" do
        allow(CognitoService).to receive(:decode_id_token).and_return({})
        allow(CognitoService).to receive(:get_user_info).and_return(valid_user_info)

        result = described_class.run(
          code: valid_code,
          state: valid_state
        )

        expect(result).to be_valid
        expect(result.result[:user].email).to eq("test@example.com")
      end

      it "uses name from userinfo endpoint when ID token decode fails" do
        userinfo_with_name = {
          "sub" => "cognito_stub_fixed_sub",
          "email" => "test@example.com",
          "name" => "UserInfo Name"
        }
        allow(CognitoService).to receive(:decode_id_token).and_return({})
        allow(CognitoService).to receive(:get_user_info).and_return(userinfo_with_name)

        result = described_class.run(
          code: valid_code,
          state: valid_state
        )

        expect(result).to be_valid
        expect(result.result[:user].name).to eq("UserInfo Name")
      end
    end

    context "on failure" do
      it "fails when code is missing" do
        result = described_class.run(code: nil, state: valid_state)
        expect(result).not_to be_valid
        expect(result.errors[:code]).to be_present
      end

      context "professional signup context validation" do
        include_context "cognito stubs"

        it "fails when professional_id is not numeric" do
          result = described_class.run(
            code: valid_code,
            state: URI.encode_www_form("professional_id" => "abc")
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Invalid professional signup context")
        end

        it "fails when professional_id does not exist" do
          result = described_class.run(
            code: valid_code,
            state: URI.encode_www_form("professional_id" => "999999")
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Invalid professional signup context")
        end
      end

      context "token exchange errors" do
        it "fails when token exchange returns invalid_grant error" do
          error_response = {
            "error" => "invalid_grant",
            "error_description" => "Authorization code expired"
          }

          allow(CognitoService).to receive(:exchange_code_for_tokens).and_return(error_response)

          result = described_class.run(
            code: "expired_code",
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("authorization code has already been used or has expired")
        end

        it "fails when token exchange returns other error" do
          error_response = {
            "error" => "invalid_client",
            "error_description" => "Client authentication failed"
          }

          allow(CognitoService).to receive(:exchange_code_for_tokens).and_return(error_response)

          result = described_class.run(
            code: "invalid_code",
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Token exchange failed: invalid_client")
        end

        it "fails when token exchange returns error without description" do
          error_response = {
            "error" => "unknown_error"
          }

          allow(CognitoService).to receive(:exchange_code_for_tokens).and_return(error_response)

          result = described_class.run(
            code: "invalid_code",
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Token exchange failed: unknown_error")
        end
      end

      context "token validation errors" do
        [
          [ :access_token, "access_token" ],
          [ :id_token, "id_token" ],
          [ :refresh_token, "refresh_token" ],
          [ :all, "access_token", "id_token", "refresh_token" ]
        ].each do |test_case|
          token_name, *missing_tokens = test_case
          it "fails when #{token_name} is missing" do
            incomplete_tokens = {
              "access_token" => missing_tokens.include?("access_token") ? nil : "token",
              "id_token" => missing_tokens.include?("id_token") ? nil : "token",
              "refresh_token" => missing_tokens.include?("refresh_token") ? nil : "token"
            }

            allow(CognitoService).to receive(:exchange_code_for_tokens).and_return(incomplete_tokens)

            result = described_class.run(
              code: valid_code,
              state: valid_state
            )

            expect(result).not_to be_valid
            expect(result.errors.full_messages.join(" ")).to include("Missing required tokens")
            missing_tokens.each do |token|
              expect(result.errors.full_messages.join(" ")).to include(token)
            end
          end
        end
      end

      context "user info errors" do
        before do
          valid_tokens = {
            "access_token" => "access_token_123",
            "id_token" => "id_token_123",
            "refresh_token" => "refresh_token_123"
          }
          allow(CognitoService).to receive(:exchange_code_for_tokens).and_return(valid_tokens)
        end

        it "fails when user info sub is missing" do
          incomplete_user_info = {
            "email" => "test@example.com"
          }

          allow(CognitoService).to receive(:decode_id_token).and_return(incomplete_user_info)
          allow(CognitoService).to receive(:get_user_info).and_return(incomplete_user_info)

          result = described_class.run(
            code: valid_code,
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Unable to retrieve user identifier")
        end

        it "fails when user info email is missing" do
          incomplete_user_info = {
            "sub" => "cognito_stub_fixed_sub"
          }

          allow(CognitoService).to receive(:decode_id_token).and_return(incomplete_user_info)

          result = described_class.run(
            code: valid_code,
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Unable to retrieve email")
        end

        it "handles error when userinfo endpoint fails" do
          allow(CognitoService).to receive(:decode_id_token).and_return({})
          allow(CognitoService).to receive(:get_user_info).and_raise(RuntimeError.new("Connection failed"))

          result = described_class.run(
            code: valid_code,
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Unable to retrieve user identifier")
        end
      end

      context "user creation errors" do
        include_context "cognito stubs"

        it "fails when cognito_id is blank in user_info" do
          # This tests the defensive check in find_or_create_user
          # Even though user_info_valid? should catch this, we test the defensive check
          user_info_without_sub = {
            "email" => "test@example.com",
            "name" => "Test User"
          }
          valid_tokens = {
            "access_token" => "access_token_123",
            "id_token" => "id_token_123",
            "refresh_token" => "refresh_token_123"
          }
          allow(CognitoService).to receive(:exchange_code_for_tokens).and_return(valid_tokens)
          allow(CognitoService).to receive(:decode_id_token).and_return(user_info_without_sub)
          allow(CognitoService).to receive(:get_user_info).and_return(user_info_without_sub)
          # Stub user_info_valid? to return true to bypass the validation and test the defensive check
          allow_any_instance_of(described_class).to receive(:user_info_valid?).and_return(true)

          result = described_class.run(
            code: valid_code,
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Cognito user ID (sub) is missing")
        end

        it "fails when user validation fails" do
          # Create a user that will fail validation by using an invalid timezone
          user_info = valid_user_info.dup
          allow(CognitoService).to receive(:decode_id_token).and_return(user_info)

          # Stub User.find_or_initialize_by to return a user that fails validation
          invalid_user = User.new(
            cognito_id: "cognito_stub_fixed_sub",
            email: "test@example.com",
            name: "Test User",
            timezone: "Invalid/Timezone",
            language: "pt"
          )
          allow(User).to receive(:find_or_initialize_by).with(cognito_id: "cognito_stub_fixed_sub").and_return(invalid_user)
          allow(invalid_user).to receive(:new_record?).and_return(true)
          allow(invalid_user).to receive(:save).and_return(false)
          invalid_user.errors.add(:timezone, "is not a valid IANA timezone identifier")

          result = described_class.run(
            code: valid_code,
            state: valid_state,
            timezone: "Invalid/Timezone"
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Failed to save user")
        end
      end

      context "patient creation errors" do
        include_context "cognito stubs"

        it "rejects signup context when parse_professional_id raises ArgumentError" do
          # Force ArgumentError by stubbing URI.decode_www_form to raise ArgumentError
          allow(URI).to receive(:decode_www_form).and_raise(ArgumentError.new("invalid byte sequence"))

          result = described_class.run(
            code: valid_code,
            state: "professional_id=1"
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Invalid professional signup context")
        end

        it "rejects signup context when parse_professional_id raises URI::InvalidURIError" do
          # Force URI::InvalidURIError by stubbing URI.decode_www_form to raise it
          allow(URI).to receive(:decode_www_form).and_raise(URI::InvalidURIError.new("invalid URI"))

          result = described_class.run(
            code: valid_code,
            state: "professional_id=1"
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Invalid professional signup context")
        end

        it "handles RecordInvalid exception when creating patient" do
          user = create(:user, cognito_id: "cognito_stub_fixed_sub")

          # Stub Patient.find_or_create_by! to raise RecordInvalid
          invalid_patient = build(:patient, user: user)
          invalid_patient.errors.add(:base, "Some validation error")
          allow(Patient).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordInvalid.new(invalid_patient))

          result = described_class.run(
            code: valid_code,
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Failed to create patient record")
        end

        it "handles RecordNotUnique exception when creating patient" do
          user = create(:user, cognito_id: "cognito_stub_fixed_sub")

          # Stub Patient.find_or_create_by! to raise RecordNotUnique
          allow(Patient).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique.new("Duplicate key"))

          result = described_class.run(
            code: valid_code,
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Patient record already exists")
        end

        it "handles generic exception when creating patient" do
          user = create(:user, cognito_id: "cognito_stub_fixed_sub")

          # Stub Patient.find_or_create_by! to raise a generic exception
          allow(Patient).to receive(:find_or_create_by!).and_raise(StandardError.new("Database connection failed"))

          result = described_class.run(
            code: valid_code,
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Failed to create patient record")
        end
      end

      context "unexpected exceptions in user creation" do
        include_context "cognito stubs"

        it "handles exception when find_or_initialize_by raises unexpected error" do
          # Stub User.find_or_initialize_by to raise an unexpected exception
          allow(User).to receive(:find_or_initialize_by).and_raise(ActiveRecord::StatementInvalid.new("Database error"))

          result = described_class.run(
            code: valid_code,
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Failed to create or find user")
          expect(result.errors.full_messages.join(" ")).to include("ActiveRecord::StatementInvalid")
        end

        it "handles exception when user.save raises unexpected error" do
          # Create a user that will raise an exception on save
          user = User.new(
            cognito_id: "cognito_stub_fixed_sub",
            email: "test@example.com",
            name: "Test",
            timezone: "America/Sao_Paulo",
            language: "pt"
          )
          allow(User).to receive(:find_or_initialize_by).and_return(user)
          allow(user).to receive(:save).and_raise(ActiveRecord::ConnectionNotEstablished.new("Connection lost"))

          result = described_class.run(
            code: valid_code,
            state: valid_state
          )

          expect(result).not_to be_valid
          expect(result.errors.full_messages.join(" ")).to include("Failed to create or find user")
          expect(result.errors.full_messages.join(" ")).to include("ActiveRecord::ConnectionNotEstablished")
        end
      end
    end
  end
end
