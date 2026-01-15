# Shared examples for auth controller specs

# Shared example for rendering error with specific status
RSpec.shared_examples "renders error with status" do |status, status_code|
  it "renders error view with #{status} status" do
    get :show, params: { code: valid_code, state: state_with_csrf }
    expect(response).to have_http_status(status)
    expect(response.status).to eq(status_code)
  end
end

# Shared example for CSRF protection tests
RSpec.shared_examples "rejects CSRF attack" do |description, setup_block|
  it description do
    instance_eval(&setup_block) if setup_block
    get :show, params: { code: valid_code, state: state_with_csrf }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include("Authentication Error")
  end
end

# Shared example for testing code idempotency
RSpec.shared_examples "rejects duplicate code" do
  it "rejects request when code was already processed" do
    Rails.cache.write("auth_code_processed:#{valid_code}", true, expires_in: 5.minutes)
    get :show, params: { code: valid_code, state: state_with_csrf }
    expect(response).to have_http_status(:bad_request)
    expect(response.body).to include("Authentication Error")
  end
end
