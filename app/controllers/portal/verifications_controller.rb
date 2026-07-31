class Portal::VerificationsController < Portal::BaseController
  include VerificationFlow

  before_action :validate_portal_return_url, only: [ :start ]
  before_action :store_return_url, only: [ :start ]

  def start
    @identity = current_identity
    status = @identity.verification_status

    case status
    when "verified"
      redirect_to_portal_return(status: :verified)
    when "pending"
      redirect_to_portal_return(status: :pending)
    when "ineligible"
      redirect_to_portal_return(status: :ineligible)
    when "needs_submission"
      redirect_to portal_verify_document_path
    end
  end

  def portal
    @identity = current_identity
    status = @identity.verification_status

    case status
    when "verified"
      redirect_to_portal_return(status: :verified)
      return
    when "pending"
      redirect_to_portal_return(status: :pending)
      return
    when "ineligible"
      redirect_to_portal_return(status: :ineligible)
      return
    end

    setup_document_step
    render :document
  end

  def cancel
    cancel_portal_flow
  end

  def create
    @identity = current_identity

    status = @identity.verification_status
    if %w[pending verified ineligible].include?(status)
      redirect_to_portal_return(status: status.to_sym)
      return
    end

    handle_document_submission
  end

  private

  def on_verification_success = redirect_to_portal_return(status: :submitted)

  def on_verification_failure = render :document
end
