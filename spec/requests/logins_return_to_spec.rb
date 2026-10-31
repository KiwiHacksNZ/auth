require "rails_helper"

RSpec.describe "Logins return_to", type: :request do
  let(:identity) { create(:identity) }
  let(:oauth_return_to) { "/oauth/authorize?client_id=nest&redirect_uri=https%3A%2F%2Fnest.kiwihacks.com%2Fcallback&response_type=code" }

  def start_attempt(return_to: oauth_return_to)
    LoginAttempt.create!(identity:, authentication_factors: {}, provenance: "login", next_action: "home", return_to:)
  end

  def sign_in_as(identity)
    allow_any_instance_of(ApplicationController).to receive(:current_identity).and_return(identity)
  end

  describe "visiting the login page while already signed in" do
    before { sign_in_as(identity) }

    it "continues to a pending OAuth return_to" do
      get login_path(return_to: oauth_return_to)

      expect(response).to redirect_to(oauth_return_to)
      expect(flash[:info]).to be_nil
    end

    it "ignores an off-site return_to" do
      get login_path(return_to: "https://evil.example/phish")

      expect(response).to redirect_to(root_path)
      expect(flash[:info]).to eq("you're already logged in, silly!")
    end

    it "ignores a protocol-relative return_to" do
      get login_path(return_to: "//evil.example/phish")

      expect(response).to redirect_to(root_path)
    end

    it "still goes home with no return_to" do
      get login_path

      expect(response).to redirect_to(root_path)
    end

    it "continues to the attempt's return_to from a second tab on the code page" do
      attempt = start_attempt

      get login_attempt_path(id: attempt.to_param)

      expect(response).to redirect_to(oauth_return_to)
    end
  end

  describe "submitting the email code twice" do
    it "sends the second submit to the client app too" do
      attempt = start_attempt
      code = Identity::V2LoginCode.generate(identity).code

      post verify_login_attempt_path(id: attempt.to_param), params: { code: }
      expect(response).to redirect_to(oauth_return_to)

      post verify_login_attempt_path(id: attempt.to_param), params: { code: }
      expect(response).to redirect_to(oauth_return_to)
    end
  end

  describe "submitting the email code twice at the same time" do
    # Simulates the first submit finishing between this request loading the attempt and
    # looking up its code.
    def finish_concurrently(attempt, code)
      allow(Identity::V2LoginCode).to receive(:active).and_wrap_original do |original|
        code.update_columns(used_at: Time.current)
        attempt.update!(authentication_factors: { email: true })
        original.call
      end
    end

    it "sends the second submit on to the client app instead of a code error" do
      attempt = start_attempt
      code = Identity::V2LoginCode.generate(identity)
      finish_concurrently(attempt, code)

      post verify_login_attempt_path(id: attempt.to_param), params: { code: code.code }

      expect(response).to redirect_to(login_path(return_to: oauth_return_to))
      expect(flash[:error]).not_to eq("Invalid or expired code, please try again")
    end

    it "sends the second submit to the next factor when 2FA is still needed" do
      totp = identity.totps.create!
      totp.mark_verified!
      identity.update!(use_two_factor_authentication: true)
      attempt = start_attempt
      code = Identity::V2LoginCode.generate(identity)
      finish_concurrently(attempt, code)

      post verify_login_attempt_path(id: attempt.to_param), params: { code: code.code }

      expect(response).to redirect_to(totp_login_attempt_path(id: attempt.to_param))
    end
  end

  describe "an attempt that can no longer be used" do
    it "keeps return_to when sending an expired attempt back to the login page" do
      attempt = start_attempt
      attempt.update_columns(created_at: (LoginAttempt::EXPIRATION + 1.minute).ago)

      get login_attempt_path(id: attempt.to_param)

      expect(response).to redirect_to(login_path(return_to: oauth_return_to))
      expect(flash[:error]).to eq("Invalid login attempt, please start again")
    end

    it "drops an unsafe stored return_to" do
      attempt = start_attempt(return_to: "https://evil.example/phish")
      attempt.update_columns(created_at: (LoginAttempt::EXPIRATION + 1.minute).ago)

      get login_attempt_path(id: attempt.to_param)

      expect(response).to redirect_to(login_path)
    end

    it "goes to the login page without return_to for an unknown attempt" do
      get login_attempt_path(id: "nonexistent")

      expect(response).to redirect_to(login_path)
    end
  end
end
