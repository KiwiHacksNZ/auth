require "rails_helper"

RSpec.describe "OAuth apps that request discord_id", type: :request do
  let(:identity) { create(:identity, discord_id: nil) }
  let(:discord_user) { { "id" => "123456789012345678", "username" => "kiki", "global_name" => "Kiki" } }
  let(:program) do
    create(:program, name: "KiwiHacks Minecraft", redirect_uri: "https://play.kiwihacks.com/login/callback",
                     scopes: "openid profile discord_id")
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

  it "leaves apps that don't request discord_id alone" do
    get "/oauth/authorize?#{authorize_params.merge(scope: "openid profile").to_query}"

    expect(response).to have_http_status(:ok)
  end

  it "only follows same-site paths on /link/discord" do
    identity.update!(discord_id: "123456789012345678")

    get discord_account_path(return_to: "//evil.example/oauth/authorize")

    expect(response).not_to be_redirect
  end
end
