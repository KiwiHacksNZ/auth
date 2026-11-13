# frozen_string_literal: true

# "Sign in with Slack" (OpenID Connect), used only to link someone's Slack account.
# https://api.slack.com/authentication/sign-in-with-slack
module SlackSignInService
  class Error < StandardError; end
  class WrongWorkspace < Error; end

  USER_ID_CLAIM = "https://slack.com/user_id"
  TEAM_ID_CLAIM = "https://slack.com/team_id"

  class << self
    def configured? = ENV["SLACK_CLIENT_ID"].present? && ENV["SLACK_CLIENT_SECRET"].present?

    # The workspace people must link from. Unset means any workspace.
    def team_id = ENV["SLACK_TEAM_ID"].presence

    def authorize_url(redirect_uri:, state:, nonce:)
      params = {
        response_type: "code",
        scope: "openid profile",
        client_id: ENV["SLACK_CLIENT_ID"],
        redirect_uri:,
        state:,
        nonce:,
        team: team_id
      }.compact

      "https://slack.com/openid/connect/authorize?#{params.to_query}"
    end

    # Exchanges an authorization code for the Slack user it belongs to.
    # Returns { id:, team_id:, name: }. Raises Error if Slack refuses, or if the
    # account is from a different workspace than SLACK_TEAM_ID.
    def fetch_user(code:, redirect_uri:)
      token = post("openid.connect.token", form: {
        client_id: ENV["SLACK_CLIENT_ID"],
        client_secret: ENV["SLACK_CLIENT_SECRET"],
        code:,
        redirect_uri:
      })

      info = JSON.parse(HTTP.auth("Bearer #{token["access_token"]}").post("https://slack.com/api/openid.connect.userInfo").body.to_s)
      raise Error, "userInfo failed (#{info["error"]})" unless info["ok"]

      user = { id: info[USER_ID_CLAIM].to_s, team_id: info[TEAM_ID_CLAIM].to_s, name: info["name"].presence || info["given_name"] }
      raise Error, "no user ID in userInfo" if user[:id].blank?
      raise WrongWorkspace if team_id && user[:team_id] != team_id

      user
    end

    private

    def post(method, form:)
      body = JSON.parse(HTTP.post("https://slack.com/api/#{method}", form:).body.to_s)
      raise Error, "#{method} failed (#{body["error"]})" unless body["ok"]

      body
    end
  end
end
