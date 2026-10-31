# frozen_string_literal: true

module DiscordService
  API_BASE = "https://discord.com/api/v10"

  class Error < StandardError; end

  class << self
    def configured? = ENV["DISCORD_CLIENT_ID"].present? && ENV["DISCORD_CLIENT_SECRET"].present?

    def authorize_url(redirect_uri:, state:)
      params = {
        client_id: ENV["DISCORD_CLIENT_ID"],
        redirect_uri:,
        response_type: "code",
        scope: "identify",
        state:,
        prompt: "consent"
      }

      "https://discord.com/oauth2/authorize?#{params.to_query}"
    end

    # Exchanges an authorization code for the Discord user it belongs to.
    # Returns the user object from /users/@me (id, username, global_name, ...).
    def fetch_user(code:, redirect_uri:)
      token_response = HTTP.post("#{API_BASE}/oauth2/token", form: {
        client_id: ENV["DISCORD_CLIENT_ID"],
        client_secret: ENV["DISCORD_CLIENT_SECRET"],
        grant_type: "authorization_code",
        code:,
        redirect_uri:
      })
      raise Error, "token exchange failed (#{token_response.status})" unless token_response.status.success?

      access_token = JSON.parse(token_response.body.to_s)["access_token"]
      user_response = HTTP.auth("Bearer #{access_token}").get("#{API_BASE}/users/@me")
      raise Error, "user lookup failed (#{user_response.status})" unless user_response.status.success?

      JSON.parse(user_response.body.to_s)
    end
  end
end
