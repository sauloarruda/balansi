# Shared examples for testing error handling patterns
RSpec.shared_examples "handles error gracefully" do |error_class, error_message_pattern|
  it "handles #{error_class} gracefully" do
    allow_any_instance_of(described_class).to receive(:execute).and_raise(error_class.new("Test error"))

    result = described_class.run(valid_params)

    expect(result).not_to be_valid
    expect(result.errors.full_messages.join(" ")).to match(error_message_pattern)
  end
end

# Shared example for testing missing required parameters
RSpec.shared_examples "requires parameter" do |param_name|
  it "fails when #{param_name} is missing" do
    params = valid_params.dup
    params.delete(param_name)

    result = described_class.run(params)

    expect(result).not_to be_valid
    expect(result.errors[param_name]).to be_present
  end
end
