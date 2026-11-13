Rails.application.config.to_prepare do
  class ActiveStorage::Blob
    before_validation :generate_encryption_key, on: :create

    private

    def generate_encryption_key
      self.encryption_key ||= SecureRandom.bytes(48)
    end
  end

  class Doorkeeper::AuthorizationsController
    include AhoyAnalytics

    layout "logged_out"
    after_action :track_oauth_denied, only: :destroy

    AUTHORIZE_PARAMS = %i[client_id redirect_uri state response_type response_mode scope nonce code_challenge code_challenge_method].freeze

    # A stale consent form fails the CSRF check, and the app-wide handler would send the
    # user to our home page instead of back to the client app. Show the consent screen
    # again for the same request instead; Doorkeeper re-validates every parameter.
    rescue_from ActionController::InvalidAuthenticityToken do
      query = params.permit(*AUTHORIZE_PARAMS).to_h.compact_blank
      if query[:client_id].present?
        redirect_to "#{oauth_authorization_path}?#{query.to_query}", status: :see_other
      else
        redirect_to root_path
      end
    end

    private

    def track_oauth_denied
      app = Program.find_by(uid: params[:client_id])
      track_event("oauth.denied",
        program_name: app&.name,
        program_id: app&.id,
        scenario: app&.onboarding_scenario
      )
    end
  end

  # Redirect URIs went unvalidated while this was disabled, so only check them when they
  # change; otherwise apps registered back then could never be saved again.
  Doorkeeper::RedirectUriValidator.prepend(Module.new do
    def validate_each(record, attribute, value)
      return if record.persisted? && !record.will_save_change_to_attribute?(attribute)

      super
    end
  end)

  # Fix public_activity 3.0.2 crash when `parameters` column contains
  # raw strings instead of YAML-deserialized hashes.
  PublicActivity::Activity.prepend(Module.new do
    def prepare_parameters(params)
      p = self.parameters
      if p.is_a?(String)
        p = (YAML.safe_load(p, permitted_classes: [ Symbol ]) rescue {}) || {}
      end
      if p.is_a?(Hash)
        @prepared_params ||= p.with_indifferent_access.merge(params)
      else
        @prepared_params ||= params
      end
    end
  end)
end
