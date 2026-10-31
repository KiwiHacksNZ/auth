require "rails_helper"

RSpec.describe Program, "redirect URI validation" do
  let(:program) { create(:program) }

  it "rejects a bad redirect URI on create" do
    expect(build(:program, redirect_uri: "javascript:alert(1)")).not_to be_valid
  end

  it "rejects a bad redirect URI when it is changed" do
    program.redirect_uri = "javascript:alert(1)"

    expect(program).not_to be_valid
  end

  it "still lets an app saved before validation was enabled be edited" do
    program.update_column(:redirect_uri, "javascript:alert(1)")

    expect(program.reload.update(name: "Renamed")).to be true
  end
end
