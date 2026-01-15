# Shared examples for testing default behavior patterns
RSpec.shared_examples "defaults to value" do |method_name, default_value, test_cases|
  describe "defaults to #{default_value}" do
    test_cases.each do |input, description|
      it description do
        result = subject.send(method_name, input)
        expect(result).to eq(default_value)
      end
    end
  end
end

# Shared example for testing default behavior in controller concerns
RSpec.shared_examples "controller default behavior" do |method_name, default_value, test_cases|
  describe "defaults to #{default_value}" do
    test_cases.each do |input_value, description|
      it description do
        # Set up input (could be header, cookie, etc.)
        if input_value.is_a?(Hash)
          input_value.each { |key, value| request.send(key)[:value] = value }
        elsif input_value.nil?
          # Don't set anything
        else
          # Default behavior - override in specific shared example
        end

        get :index
        result = controller.send(method_name)
        expect(result).to eq(default_value)
      end
    end
  end
end
