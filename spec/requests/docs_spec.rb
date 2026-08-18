require "rails_helper"

RSpec.describe "Docs", type: :request do
  describe "hosting information" do
    it "describes the shared server on the security page" do
      get doc_path(slug: "security")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("The identity platform runs on the same server as KiwiHacks&#39; other services.")
      expect(response.body).not_to include("dedicated server")
    end

    it "describes the shared server on the privacy page" do
      get doc_path(slug: "privacy")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your data is stored on the same server as KiwiHacks&#39; other services.")
      expect(response.body).not_to include("server separate from")
    end
  end
end
