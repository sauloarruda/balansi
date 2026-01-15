# Helper methods for mocking Rails.application.credentials in CognitoService specs
require "ostruct"

module CognitoCredentialsHelper
  def mock_credentials(credentials_hash = nil)
    test_hash = credentials_hash || test_credentials_hash
    @original_credentials_method = Rails.application.method(:credentials) if Rails.application.respond_to?(:credentials)

    Rails.application.define_singleton_method(:credentials) do |_env = nil|
      creds = OpenStruct.new
      creds.define_singleton_method(:dig) do |*args|
        test_hash.dig(*args)
      end
      creds
    end
  end

  def restore_credentials
    if @original_credentials_method
      Rails.application.define_singleton_method(:credentials, @original_credentials_method)
    end
  end
end
