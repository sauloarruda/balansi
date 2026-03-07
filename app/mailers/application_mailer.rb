class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM", "no-reply@#{ENV.fetch("APP_HOST", "example.com")}") }
  layout "mailer"
end
