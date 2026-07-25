class ApplicationMailer < ActionMailer::Base
  include Rails.application.routes.url_helpers
  layout "mailer"

  ACCOUNT_FROM = "KiwiHacks <niko@kiwihacks.org>".freeze
  IDENTITY_FROM = "KiwiHacks <niko@kiwihacks.org>".freeze

  private

  def env_prefix
    case Rails.env
    when "development" then "[DEV] "
    when "staging" then "[STAGING] "
    else ""
    end
  end

  def prefixed_subject(subject)
    "#{env_prefix}#{subject}"
  end
end
