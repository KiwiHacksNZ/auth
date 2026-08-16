class Tutorial::WelcomeMessageJob < ApplicationJob
  queue_as :default

  BOT_NAME = "the Viceroy of Virtuous Conduct"
  BOT_ICON_URL = ENV["CONDUCT_BOT_ICON_URL"].presence

  def perform(identity)
    RalseiEngine.send_message(identity, "tutorial/welcome_to_kiwihacks", bot_name: BOT_NAME, bot_icon_url: BOT_ICON_URL)
  end
end
