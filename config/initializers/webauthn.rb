# Configure WebAuthn for passkey authentication
WebAuthn.configure do |config|
  # rp_id must equal, or be a registrable suffix of, the host actually serving the
  # page — browsers reject registration otherwise — so it tracks APP_HOST rather
  # than a hardcoded domain.
  host = ENV.fetch("APP_HOST") { Rails.env.production? ? "account.kiwihacks.com" : "localhost:3000" }
  scheme = host.start_with?("localhost") ? "http" : "https"

  config.allowed_origins = [ "#{scheme}://#{host}" ]
  config.rp_name = "KiwiHacks Account"
  config.rp_id = host.split(":").first
  config.algorithms = [ "ES256", "RS256" ]
end
