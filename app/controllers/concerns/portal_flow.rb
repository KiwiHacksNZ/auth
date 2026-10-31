module PortalFlow
  extend ActiveSupport::Concern
  include ProgramReturnUrl

  included do
    before_action :validate_portal_return_url, only: [ :portal ]
    before_action :store_return_url, only: [ :portal ]
    helper_method :portal_onboarding_scenario
  end

  private

  def portal_return_url
    session[:portal_return_to]
  end

  def portal_program
    @portal_program ||= Program.find_by_redirect_uri_host(portal_return_url)
  end

  def portal_onboarding_scenario
    return @portal_onboarding_scenario if defined?(@portal_onboarding_scenario)
    scenario_class = portal_program&.onboarding_scenario_class
    @portal_onboarding_scenario = scenario_class&.new(current_identity)
  end

  def store_return_url
    session[:portal_return_to] = validated_return_url if params[:return_to].present?
  end

  def validate_portal_return_url
    unless validated_return_url || session[:portal_return_to]
      flash[:error] = "Invalid or missing return URL"
      redirect_to root_path
    end
  end

  def redirect_to_portal_return(status: :success, notice: nil)
    return_url = portal_return_url
    session.delete(:portal_return_to)

    uri = URI.parse(return_url)
    params = URI.decode_www_form(uri.query || "").to_h
    params["portal_status"] = status.to_s
    uri.query = URI.encode_www_form(params)

    redirect_to uri.to_s, notice: notice, allow_other_host: true
  end

  def cancel_portal_flow = redirect_to_portal_return(status: :canceled)

  def redirect_to_simple_return
    return_url = portal_return_url
    session.delete(:portal_return_to)
    redirect_to return_url || root_path, allow_other_host: true
  end
end
