require "rails_helper"

RSpec.describe "Verifications", type: :request do
  let(:identity) { create(:identity) }
  let(:session) do
    identity.sessions.create!(
      session_token: SecureRandom.hex(32),
      expires_at: 1.week.from_now
    )
  end

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_session).and_return(session)
    allow_any_instance_of(ApplicationController).to receive(:identity_signed_in?).and_return(true)
  end

  describe "GET /verifications/status" do
    it "shows not started when no verifications exist" do
      get verification_status_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("not started").or include("Not started").or include("not_started")
    end
  end

  describe "GET /verifications/new" do
    it "redirects to the document step" do
      get new_verifications_path
      expect(response).to redirect_to(verification_step_path(:document))
    end
  end
end
