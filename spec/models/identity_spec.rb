require "rails_helper"

RSpec.describe Identity, type: :model do
  let(:identity) { create(:identity) }

  describe "#onboarding_step" do
    before { Flipper.enable(:identity_verification_required_2026_07_25, identity) }
    after { Flipper.disable(:identity_verification_required_2026_07_25) }

    it "returns :document when no verification exists" do
      expect(identity.onboarding_step).to eq(:document)
    end

    it "returns :address when verification is pending but no address" do
      create(:document_verification, identity: identity)
      expect(identity.onboarding_step).to eq(:address)
    end

    it "returns :submitted when verification exists and address is set" do
      create(:document_verification, identity: identity, status: :approved)
      address = create(:address, identity: identity)
      identity.update!(primary_address: address)
      expect(identity.onboarding_step).to eq(:submitted)
    end
  end

  describe "#needs_documents?" do
    before { Flipper.enable(:identity_verification_required_2026_07_25, identity) }
    after { Flipper.disable(:identity_verification_required_2026_07_25) }

    it "returns true when no verification exists" do
      expect(identity.needs_documents?).to be true
    end

    it "returns false once a verification is pending" do
      create(:document_verification, identity: identity)
      expect(identity.needs_documents?).to be false
    end

    it "returns false when identity verification is disabled" do
      Flipper.disable(:identity_verification_required_2026_07_25, identity)
      expect(identity.needs_documents?).to be false
    end
  end
end
