class VerificationsController < ApplicationController
  include Wicked::Wizard
  include VerificationFlow
  include AhoyAnalytics

  before_action :set_identity
  before_action :ensure_idv_enabled

  steps :document

  def new
    status = current_identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    redirect_to verification_step_path(:document)
  end

  def status
    @identity = current_identity
    @status = @identity.verification_status
    @latest_verification = @identity.latest_verification

    # Draft aadhaar verifications mean the user has started an async
    # flow — show "pending" instead of "not started" while we wait for the webhook.
    if @status == "needs_submission" && @identity.verifications.not_ignored.where(status: :draft).any?
      @status = "pending"
    end
  end

  def status_check
    status = current_identity.verification_status
    if status == "needs_submission" && current_identity.verifications.not_ignored.where(status: :draft).any?
      status = "pending"
    end
    render json: { status: }
  end

  def show
    @identity = current_identity

    status = @identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    case step
    when :document
      setup_document_step
    end

    render_wizard
  end

  def update
    @identity = current_identity

    status = @identity.verification_status
    if verification_should_redirect?(status)
      redirect_to verification_status_path
      return
    end

    case step
    when :document
      handle_document_submission
    end
  end

  private

  def set_identity
    @identity = current_identity
  end

  # ID verification is disabled globally for now — block direct access to the flow.
  def ensure_idv_enabled
    redirect_to root_path unless current_identity&.identity_verification_enabled?
  end

  def on_verification_success
    track_event("verification.submitted", verification_type: "document", scenario: analytics_scenario_for(@identity))
    flash[:success] = "Your documents have been submitted for review! We'll email you when they're processed."
    redirect_to root_path
  end

  def on_verification_failure = render_wizard
end
