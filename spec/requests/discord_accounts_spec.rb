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
