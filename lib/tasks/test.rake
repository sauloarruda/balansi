# Override Rails test command by creating a custom Rails command
# Note: This works for rake test, but rails test uses a different mechanism
# For rails test, users should use: bundle exec rspec or rake test

desc "Run RSpec tests (aliased from test)"
task test: :environment do
  sh "bundle exec rspec"
end

namespace :test do
  desc "Run RSpec tests"
  task all: :environment do
    sh "bundle exec rspec"
  end
end
