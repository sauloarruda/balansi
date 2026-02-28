# Shared context for Cognito service stubs
RSpec.shared_context "cognito stubs" do
  let(:valid_tokens) do
    {
      "access_token" => "access_token_123",
      "id_token" => "id_token_123",
      "refresh_token" => "refresh_token_123"
    }
  end

  let(:valid_user_info) do
    {
      "sub" => "cognito_stub_fixed_sub",
      "email" => "test@example.com",
      "name" => "Test User"
    }
  end

  before do
    allow(CognitoService).to receive(:exchange_code_for_tokens).and_return(valid_tokens)
    allow(CognitoService).to receive(:decode_id_token).and_return(valid_user_info)
  end
end
