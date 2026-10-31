require "rails_helper"

RSpec.describe "DiscordAccounts", type: :request do
  let(:identity) { create(:identity, discord_id: nil) }
  let(:discord_user) { { "id" => "123456789012345678", "username" => "kiki", "global_name" => "Kiki" } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_ID").and_return("client-id")
    allow(ENV).to receive(:[]).with("DISCORD_CLIENT_SECRET").and_return("client-secret")
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
  end

  def start_link
    post discord_account_path
    Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
  end

  def stub_discord(user: discord_user)
    allow(DiscordService).to receive(:fetch_user).and_return(user)
  end

  describe "POST /link/discord" do
    it "redirects to Discord with the identify scope and a state" do
      post discord_account_path
      uri = URI.parse(response.location)
      query = Rack::Utils.parse_query(uri.query)

      expect(uri.host).to eq("discord.com")
      expect(query).to include("scope" => "identify", "client_id" => "client-id",
                               "redirect_uri" => callback_discord_account_url)
      expect(query["state"]).to be_present
    end
  end

  describe "GET /link/discord/callback" do
    it "saves the Discord ID when the state matches" do
      stub_discord
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(DiscordService).to have_received(:fetch_user).with(code: "abc", redirect_uri: callback_discord_account_url)
      expect(response).to redirect_to(discord_account_path)
      expect(identity.reload.discord_id).to eq("123456789012345678")
    end

    it "rejects a mismatched state" do
      stub_discord
      start_link

      get callback_discord_account_path(code: "abc", state: "forged")

      expect(identity.reload.discord_id).to be_nil
      expect(DiscordService).not_to have_received(:fetch_user)
    end

    it "rejects a callback with no link in progress" do
      get callback_discord_account_path(code: "abc", state: "anything")
      expect(identity.reload.discord_id).to be_nil
    end

    it "refuses a Discord account linked to someone else" do
      create(:identity, discord_id: "123456789012345678")
      stub_discord
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(identity.reload.discord_id).to be_nil
      expect(flash[:error]).to be_present
    end

    it "handles the user cancelling on Discord" do
      state = start_link
      get callback_discord_account_path(error: "access_denied", state:)
      expect(identity.reload.discord_id).to be_nil
      expect(flash[:info]).to be_present
    end

    it "handles Discord being unavailable" do
      allow(DiscordService).to receive(:fetch_user).and_raise(DiscordService::Error, "token exchange failed (500)")
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(identity.reload.discord_id).to be_nil
      expect(flash[:error]).to be_present
    end
  end

  describe "?source=mclink" do
    let(:mc_resume) { "https://mc.kiwihacks.com/link/resume" }

    it "sends people back to Minecraft linking after they link Discord" do
      stub_discord
      get discord_account_path(source: "mclink")
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(response).to redirect_to(mc_resume)
      expect(identity.reload.discord_id).to eq("123456789012345678")
    end

    it "sends people who already have Discord linked straight back" do
      identity.update!(discord_id: "123456789012345678")

      get discord_account_path(source: "mclink")

      expect(response).to redirect_to(mc_resume)
    end

    it "ignores unknown sources" do
      stub_discord
      get discord_account_path(source: "https://evil.example")
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(response).to redirect_to(discord_account_path)
    end

    it "forgets the source when the page is opened again without one" do
      stub_discord
      get discord_account_path(source: "mclink")
      get discord_account_path
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(response).to redirect_to(discord_account_path)
    end

    it "stays on the page if linking fails" do
      allow(DiscordService).to receive(:fetch_user).and_raise(DiscordService::Error, "down")
      get discord_account_path(source: "mclink")
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(response).to redirect_to(discord_account_path)
    end
  end

  describe "?return_to=" do
    let(:resume) { "https://mc.kiwihacks.com/link/resume?player=abc" }

    before { create(:program, redirect_uri: "https://mc.kiwihacks.com/oauth/callback") }

    it "sends people back to an official app after they link Discord" do
      stub_discord
      get discord_account_path(return_to: resume)
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(response).to redirect_to(resume)
      expect(identity.reload.discord_id).to eq("123456789012345678")
    end

    it "sends people who already have Discord linked straight back" do
      identity.update!(discord_id: "123456789012345678")

      get discord_account_path(return_to: resume)

      expect(response).to redirect_to(resume)
    end

    it "ignores hosts that aren't an official app's" do
      stub_discord
      get discord_account_path(return_to: "https://evil.example/link")
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(response).to redirect_to(discord_account_path)
    end

    it "ignores non-http URLs on an official host" do
      identity.update!(discord_id: "123456789012345678")

      get discord_account_path(return_to: "javascript://mc.kiwihacks.com/%0aalert(1)")

      expect(response.location).not_to start_with("javascript")
    end
  end

  describe "GET /portal/discord" do
    let(:return_to) { "https://mc.kiwihacks.com/link/resume" }

    before { create(:program, redirect_uri: "https://mc.kiwihacks.com/oauth/callback") }

    it "asks people without Discord linked to link it" do
      get portal_discord_path(return_to:)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(discord_account_path)
    end

    it "sends people who already have Discord linked straight back" do
      identity.update!(discord_id: "123456789012345678")

      get portal_discord_path(return_to:)

      expect(response).to redirect_to("#{return_to}?portal_status=linked")
    end

    it "sends people back once they link Discord" do
      stub_discord
      get portal_discord_path(return_to:)
      state = start_link

      get callback_discord_account_path(code: "abc", state:)
      expect(response).to redirect_to(portal_discord_path)
      follow_redirect!

      expect(response).to redirect_to("#{return_to}?portal_status=linked")
      expect(identity.reload.discord_id).to eq("123456789012345678")
    end

    it "keeps people on the portal page if linking fails" do
      allow(DiscordService).to receive(:fetch_user).and_raise(DiscordService::Error, "down")
      get portal_discord_path(return_to:)
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(response).to redirect_to(portal_discord_path)
      expect(flash[:error]).to be_present
    end

    it "sends people back as canceled when they go back without linking" do
      get portal_discord_path(return_to:)

      delete portal_discord_path

      expect(response).to redirect_to("#{return_to}?portal_status=canceled")
    end

    it "rejects a return_to that isn't an official app's" do
      get portal_discord_path(return_to: "https://evil.example/")

      expect(response).to redirect_to(root_path)
    end

    it "stops returning to the portal once the account page is opened directly" do
      stub_discord
      get portal_discord_path(return_to:)
      get discord_account_path
      state = start_link

      get callback_discord_account_path(code: "abc", state:)

      expect(response).to redirect_to(discord_account_path)
    end
  end

  describe "DELETE /link/discord" do
    it "clears the Discord ID" do
      identity.update!(discord_id: "123456789012345678")
      delete discord_account_path
      expect(identity.reload.discord_id).to be_nil
    end

    it "keeps the same callback state from being reused" do
      stub_discord
      state = start_link
      get callback_discord_account_path(code: "abc", state:)
      delete discord_account_path

      get callback_discord_account_path(code: "abc", state:)

      expect(identity.reload.discord_id).to be_nil
    end
  end
end
