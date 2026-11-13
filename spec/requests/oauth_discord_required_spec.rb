require "rails_helper"

RSpec.describe "OAuth apps that require Discord", type: :request do
  let(:identity) { create(:identity, discord_id: nil, slack_id: nil) }
  let(:discord_user) { { "id" => "123456789012345678", "username" => "kiki", "global_name" => "Kiki" } }
  let(:program) do
    create(:program, name: "KiwiHacks Minecraft", redirect_uri: "https://play.kiwihacks.com/login/callback",
                     scopes: "openid profile discord_id", requires_discord: true)
  end
  let(:authorize_params) do
    {
      response_type: "code", client_id: program.uid, redirect_uri: "https://play.kiwihacks.com/login/callback",
      scope: "openid profile discord_id", state: "st4te", nonce: "n0nce",
      code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", code_challenge_method: "S256"
    }
  end
  let(:authorize_path) { "/oauth/authorize?#{authorize_params.to_query}" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_ID").and_return("client-id")
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_SECRET").and_return("client-secret")
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
  end

  def link_discord(error: nil)
    post discord_account_path
    state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
    params = error ? { error:, state: } : { code: "abc", state: }
    get callback_discord_account_path(params)
  end

  it "sends people without Discord to link it, naming the app" do
    get authorize_path

    expect(response).to redirect_to("/link/discord?#{{ return_to: authorize_path }.to_query}")
    expect(flash[:info]).to include("KiwiHacks Minecraft")
  end

  it "returns to the same authorize request, every parameter intact, once Discord is linked" do
    allow(DiscordService).to receive(:fetch_user).and_return(discord_user)
    get authorize_path
    follow_redirect!

    link_discord

    expect(response).to redirect_to(authorize_path)
    expect(identity.reload.discord_id).to eq("123456789012345678")
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("KiwiHacks Minecraft")
  end

  it "keeps people on the link page if they cancel on Discord, and still returns after a retry" do
    allow(DiscordService).to receive(:fetch_user).and_return(discord_user)
    get authorize_path
    follow_redirect!

    link_discord(error: "access_denied")
    expect(response).to redirect_to(discord_account_path)
    expect(identity.reload.discord_id).to be_nil

    link_discord
    expect(response).to redirect_to(authorize_path)
  end

  it "keeps people on the link page if that Discord account belongs to someone else" do
    create(:identity, discord_id: "123456789012345678")
    allow(DiscordService).to receive(:fetch_user).and_return(discord_user)
    get authorize_path
    follow_redirect!

    link_discord

    expect(response).to redirect_to(discord_account_path)
    expect(flash[:error]).to be_present
    expect(identity.reload.discord_id).to be_nil
  end

  it "never issues a code to someone without Discord" do
    post "/oauth/authorize", params: authorize_params

    expect(response).to redirect_to("/link/discord")
    expect(response.location).not_to include("code=")
  end

  it "goes straight to consent for people with Discord linked" do
    identity.update!(discord_id: "123456789012345678")

    get authorize_path

    expect(response).to have_http_status(:ok)
  end

  it "still requires Discord when the app doesn't request discord_id" do
    path = "/oauth/authorize?#{authorize_params.merge(scope: "openid profile").to_query}"
    get path

    expect(response).to redirect_to("/link/discord?#{{ return_to: path }.to_query}")
  end

  it "goes straight to consent for an app that requests discord_id without requiring it" do
    program.update!(requires_discord: false)

    get authorize_path

    expect(response).to have_http_status(:ok)
  end

  it "lets people deny an app that requires Discord without linking it" do
    delete "/oauth/authorize", params: authorize_params

    expect(response.location).to start_with("https://play.kiwihacks.com/login/callback?error=access_denied")
    expect(response.location).to include("state=st4te")
  end

  describe "apps that require Slack" do
    before { program.update!(requires_discord: false, requires_slack: true, scopes: "openid profile slack_id") }

    let(:slack_params) { authorize_params.merge(scope: "openid profile slack_id") }
    let(:slack_path) { "/oauth/authorize?#{slack_params.to_query}" }

    it "sends people without Slack to link it, naming the app" do
      get slack_path

      expect(response).to redirect_to("/link/slack?#{{ return_to: slack_path }.to_query}")
      expect(flash[:info]).to eq("KiwiHacks Minecraft needs your Slack account. Link it to carry on signing in.")
    end

    it "returns to the authorize request once Slack is linked, then shows consent" do
      allow(SlackSignInService).to receive(:fetch_user).and_return(id: "U012AB3CD", team_id: "T0KIWI", name: "Kiki")
      allow(ENV).to receive(:[]).with("SLACK_CLIENT_ID").and_return("slack-client")
      allow(ENV).to receive(:[]).with("SLACK_CLIENT_SECRET").and_return("slack-secret")
      get slack_path
      follow_redirect!

      post slack_account_path
      state = Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
      get callback_slack_account_path(code: "abc", state:)

      expect(response).to redirect_to(slack_path)
      follow_redirect!
      expect(response).to have_http_status(:ok)
    end

    it "goes straight to consent for people with Slack linked" do
      identity.update!(slack_id: "U012AB3CD")

      get slack_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "apps that require both" do
    before { program.update!(requires_slack: true) }

    it "asks for Discord first, then Slack, then shows consent" do
      get authorize_path
      expect(response).to redirect_to("/link/discord?#{{ return_to: authorize_path }.to_query}")

      identity.update!(discord_id: "123456789012345678")
      get authorize_path
      expect(response).to redirect_to("/link/slack?#{{ return_to: authorize_path }.to_query}")

      identity.update!(slack_id: "U012AB3CD")
      get authorize_path
      expect(response).to have_http_status(:ok)
    end
  end

  it "only follows same-site paths on /link/discord" do
    identity.update!(discord_id: "123456789012345678")

    get discord_account_path(return_to: "//evil.example/oauth/authorize")

    expect(response).not_to be_redirect
  end
end
