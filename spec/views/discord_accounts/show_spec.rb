require "rails_helper"

RSpec.describe "discord_accounts/show", type: :view do
  let(:identity) { build_stubbed(:identity, discord_id: nil) }

  before do
    assign(:identity, identity)
    allow(DiscordService).to receive(:configured?).and_return(true)
  end

  it "offers to link when no Discord account is linked" do
    render
    expect(rendered).to include("Continue to Discord")
    expect(rendered).not_to include("Unlink Discord")
  end

  it "shows the linked Discord ID with an unlink button" do
    identity.discord_id = "123456789012345678"
    render
    expect(rendered).to include("123456789012345678")
    expect(rendered).to include("Unlink Discord")
    expect(rendered).not_to include("Continue to Discord")
  end

  it "explains when Discord isn't configured on the server" do
    allow(DiscordService).to receive(:configured?).and_return(false)
    render
    expect(rendered).to include("set up on this server yet")
    expect(rendered).not_to include("Continue to Discord")
  end
end
