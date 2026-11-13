require "rails_helper"

RSpec.describe "SlackAccounts", type: :request do
  let(:identity) { create(:identity, slack_id: nil) }
  let(:slack_user) { { id: "U012AB3CD", team_id: "T0KIWI", name: "Kiki" } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SLACK_CLIENT_ID").and_return("slack-client")
    allow(ENV).to receive(:[]).with("SLACK_CLIENT_SECRET").and_return("slack-secret")
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
  end

  def start_link
    post slack_account_path
    Rack::Utils.parse_query(URI.parse(response.location).query)["state"]
  end

  it "shows a link button when Slack isn't linked" do
    get slack_account_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Continue to Slack")
  end

  it "says linking isn't set up when there are no Slack credentials" do
    allow(ENV).to receive(:[]).with("SLACK_CLIENT_ID").and_return(nil)

    get slack_account_path

    expect(response.body).to include("isn&#39;t set up")
  end

  it "redirects to Sign in with Slack with a state" do
    post slack_account_path
    uri = URI.parse(response.location)

    expect(uri.host).to eq("slack.com")
    expect(uri.path).to eq("/openid/connect/authorize")
    expect(Rack::Utils.parse_query(uri.query)["redirect_uri"]).to eq(callback_slack_account_url)
  end

  it "saves the Slack ID when the state matches" do
    allow(SlackSignInService).to receive(:fetch_user).and_return(slack_user)
    state = start_link

    get callback_slack_account_path(code: "abc", state:)

    expect(SlackSignInService).to have_received(:fetch_user).with(code: "abc", redirect_uri: callback_slack_account_url)
    expect(response).to redirect_to(slack_account_path)
    expect(identity.reload.slack_id).to eq("U012AB3CD")
    expect(flash[:success]).to include("Kiki")
  end

  it "accepts Enterprise Grid (W…) user IDs" do
    allow(SlackSignInService).to receive(:fetch_user).and_return(slack_user.merge(id: "W012AB3CD"))
    state = start_link

    get callback_slack_account_path(code: "abc", state:)

    expect(identity.reload.slack_id).to eq("W012AB3CD")
  end

  it "rejects a mismatched state" do
    allow(SlackSignInService).to receive(:fetch_user).and_return(slack_user)
    start_link

    get callback_slack_account_path(code: "abc", state: "forged")

    expect(identity.reload.slack_id).to be_nil
    expect(SlackSignInService).not_to have_received(:fetch_user)
  end

  it "refuses a Slack account linked to someone else" do
    create(:identity, slack_id: "U012AB3CD")
    allow(SlackSignInService).to receive(:fetch_user).and_return(slack_user)
    state = start_link

    get callback_slack_account_path(code: "abc", state:)

    expect(identity.reload.slack_id).to be_nil
    expect(flash[:error]).to include("different KiwiHacks account")
  end

  it "refuses an account from another workspace" do
    allow(SlackSignInService).to receive(:fetch_user).and_raise(SlackSignInService::WrongWorkspace)
    state = start_link

    get callback_slack_account_path(code: "abc", state:)

    expect(identity.reload.slack_id).to be_nil
    expect(flash[:error]).to include("isn't in the KiwiHacks workspace")
  end

  it "handles the user cancelling on Slack" do
    state = start_link

    get callback_slack_account_path(error: "access_denied", state:)

    expect(flash[:info]).to be_present
    expect(identity.reload.slack_id).to be_nil
  end

  it "handles Slack being unavailable" do
    allow(SlackSignInService).to receive(:fetch_user).and_raise(SlackSignInService::Error, "down")
    state = start_link

    get callback_slack_account_path(code: "abc", state:)

    expect(flash[:error]).to be_present
  end

  it "returns to a same-site path after linking, and straight away if already linked" do
    allow(SlackSignInService).to receive(:fetch_user).and_return(slack_user)
    get slack_account_path(return_to: "/oauth/authorize?client_id=x&state=y")
    state = start_link

    get callback_slack_account_path(code: "abc", state:)
    expect(response).to redirect_to("/oauth/authorize?client_id=x&state=y")

    get slack_account_path(return_to: "/oauth/authorize?client_id=x&state=z")
    expect(response).to redirect_to("/oauth/authorize?client_id=x&state=z")
  end

  it "ignores an off-site return_to" do
    identity.update!(slack_id: "U012AB3CD")

    get slack_account_path(return_to: "//evil.example/")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Unlink")
  end
end
