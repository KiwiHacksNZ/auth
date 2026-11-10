# Checks a ?return_to= URL against the redirect URI hosts of official programs,
# so it can be redirected to without being an open redirect. Only https is
# accepted in production; http and localhost are allowed in development.
module ProgramReturnUrl
  extend ActiveSupport::Concern

  private

  def validated_return_url
    return @validated_return_url if defined?(@validated_return_url)

    url = params[:return_to]
    return @validated_return_url = nil if url.blank?

    begin
      uri = URI.parse(url)
      host = uri.host
      return @validated_return_url = nil unless host && allowed_return_scheme?(uri.scheme)

      allowed_hosts = Program.official.pluck(:redirect_uri).flat_map { |uris|
        uris.to_s.split("\n").filter_map { |u| URI.parse(u).host rescue nil }
      }.uniq
      allowed_hosts << "localhost" unless Rails.env.production?

      @validated_return_url = allowed_hosts.include?(host) ? url : nil
    rescue URI::InvalidURIError
      @validated_return_url = nil
    end
  end

  def allowed_return_scheme?(scheme)
    scheme == "https" || (scheme == "http" && !Rails.env.production?)
  end
end
