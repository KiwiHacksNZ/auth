require "rails_helper"

RSpec.describe Rack::Attack do
  def discriminator(name, path:, method: "POST", params: {}, ip: "203.0.113.7")
    env = Rack::MockRequest.env_for(path, method:, params:, "REMOTE_ADDR" => ip)
    described_class.throttles.fetch(name).block.call(Rack::Attack::Request.new(env))
  end

  describe "signup throttles" do
    it "keys signups by email so one venue IP isn't a single bucket" do
      expect(discriminator("signup/email", path: "/signup", params: { identity: { primary_email: " Kiki@KiwiHacks.org " } })).to eq("kiki@kiwihacks.org")
      expect(described_class.throttles.fetch("signup/ip").limit).to be >= 100
    end

    it "ignores a non-hash identity param" do
      expect(discriminator("signup/email", path: "/signup", params: { identity: "x" })).to be_nil
    end

    it "does not count GET requests" do
      expect(discriminator("signup/ip", path: "/signup", method: "GET")).to be_nil
    end
  end
end
