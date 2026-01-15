# Shared context for testing controller concerns
RSpec.shared_context "controller concern test" do |options = {}|
  controller(ApplicationController) do
    # Allow custom skip_before_action configuration
    if options[:skip_auth] == :partial
      skip_before_action :authenticate_user!, only: options[:skip_auth_actions] || [ :public_action ]
    elsif options[:skip_auth] != false
      skip_before_action :authenticate_user!
    end

    # Default action
    def index
      # Call detect_browser_timezone to ensure it's executed during tests
      # This helps with code coverage for the BrowserTimezone concern
      detect_browser_timezone if respond_to?(:detect_browser_timezone, true)
      head :ok
    end

    # Allow custom actions to be defined via block
    if options[:actions]
      options[:actions].each do |action_name|
        define_method(action_name) { head :ok }
      end
    end
  end

  before do
    routes.draw do
      # Default route
      get "index", to: "anonymous#index" unless options[:skip_default_route]

      # Custom routes
      if options[:routes]
        options[:routes].each do |route|
          get route[:path], to: "anonymous##{route[:action]}"
        end
      end
    end
  end
end
