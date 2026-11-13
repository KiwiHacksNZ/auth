require "rails_helper"

RSpec.describe "Developer apps: sign-in requirements", type: :request do
  let(:owner) { create(:identity, :developer) }
  let(:program) do
    create(:program, owner_identity: owner, trust_level: :community_untrusted,
                     redirect_uri: "https://example.com/callback", scopes: "openid profile discord_id")
  end

  before { allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(owner) }

  it "is off by default" do
    expect(program.requires_discord?).to be(false)
  end

  it "shows the setting on the edit page" do
    get edit_developer_app_path(program)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("program[requires_discord]")
    expect(response.body).to include("Require a linked Discord account")
  end

  it "lets the owner turn it on and off" do
    patch developer_app_path(program), params: { program: { name: program.name, requires_discord: "1" } }
    expect(program.reload.requires_discord?).to be(true)

    get developer_app_path(program)
    expect(response.body).to include("Required to sign in")

    patch developer_app_path(program), params: { program: { name: program.name, requires_discord: "0" } }
    expect(program.reload.requires_discord?).to be(false)
  end

  it "lets the owner require Slack too" do
    get edit_developer_app_path(program)
    expect(response.body).to include("program[requires_slack]")

    patch developer_app_path(program), params: { program: { name: program.name, requires_slack: "1" } }

    expect(program.reload.requires_slack?).to be(true)
    expect(program.requires_discord?).to be(false)
    get developer_app_path(program)
    expect(response.body).to match(/Slack.*Required to sign in/m)
  end

  it "doesn't let someone who can't edit the app change it" do
    other = create(:identity, :developer)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(other)

    patch developer_app_path(program), params: { program: { name: program.name, requires_discord: "1", requires_slack: "1" } }

    expect(program.reload.requires_discord?).to be(false)
    expect(program.requires_slack?).to be(false)
  end
end
