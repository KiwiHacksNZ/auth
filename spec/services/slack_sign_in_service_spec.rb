require "rails_helper"
require "webmock"
WebMock.disable! # only for the examples below; the rest of the suite is untouched

RSpec.describe SlackSignInService do
  include WebMock::API

  around do |example|
    WebMock.enable!
    WebMock.disable_net_connect!
    example.run
  ensure
    WebMock.reset!
    WebMock.allow_net_connect!
    WebMock.disable!
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SLACK_CLIENT_ID").and_return("slack-client")
    allow(ENV).to receive(:[]).with("SLACK_CLIENT_SECRET").and_return("slack-secret")
    allow(ENV).to receive(:[]).with("SLACK_TEAM_ID").and_return("T0KIWI")
  end

  def stub_slack(team_id: "T0KIWI", token_ok: true)
    stub_request(:post, "https://slack.com/api/openid.connect.token")
      .with(body: hash_including("client_id" => "slack-client", "client_secret" => "slack-secret", "code" => "abc",
                                 "redirect_uri" => "https://account.example/link/slack/callback"))
      .to_return(body: (token_ok ? { ok: true, access_token: "xoxp-1" } : { ok: false, error: "invalid_code" }).to_json)
    stub_request(:post, "https://slack.com/api/openid.connect.userInfo")
      .with(headers: { "Authorization" => "Bearer xoxp-1" })
      .to_return(body: { ok: true, "https://slack.com/user_id" => "U012AB3CD", "https://slack.com/team_id" => team_id, name: "Kiki" }.to_json)
  end

  it "builds an authorize URL locked to the workspace" do
    query = Rack::Utils.parse_query(URI.parse(described_class.authorize_url(redirect_uri: "https://r/cb", state: "s", nonce: "n")).query)

    expect(query).to include("scope" => "openid profile", "client_id" => "slack-client", "team" => "T0KIWI",
                             "state" => "s", "nonce" => "n", "response_type" => "code")
  end

  it "returns the Slack user" do
    stub_slack

    user = described_class.fetch_user(code: "abc", redirect_uri: "https://account.example/link/slack/callback")

    expect(user).to eq(id: "U012AB3CD", team_id: "T0KIWI", name: "Kiki")
  end

  it "rejects accounts from another workspace" do
    stub_slack(team_id: "T0OTHER")

    expect { described_class.fetch_user(code: "abc", redirect_uri: "https://account.example/link/slack/callback") }
      .to raise_error(SlackSignInService::WrongWorkspace)
  end

  it "raises when Slack refuses the code" do
    stub_slack(token_ok: false)

    expect { described_class.fetch_user(code: "abc", redirect_uri: "https://account.example/link/slack/callback") }
      .to raise_error(SlackSignInService::Error, /invalid_code/)
  end
end
