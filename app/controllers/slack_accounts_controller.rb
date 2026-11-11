# Lets people link their Slack account (Sign in with Slack) at /link/slack.
# Mirrors DiscordAccountsController: ?return_to= sends them back afterwards,
# either to a same-site path (e.g. a waiting /oauth/authorize request) or to a
# URL on an official app's redirect URI host.
#
# There's no self-service unlink: slack_id also drives workspace provisioning,
# so admins clear it from the backend instead.
class SlackAccountsController < ApplicationController
  include ProgramReturnUrl
  include SafeUrlValidation

  def show
    @identity = current_identity
    session[:slack_link_return_to] = url_from(params[:return_to]) || validated_return_url

    if @identity.slack_id.present? && (url = return_url)
      redirect_to url, allow_other_host: true
    end
  end

  def create
    return redirect_to(slack_account_path) unless SlackSignInService.configured?

    state = SecureRandom.hex(24)
    nonce = SecureRandom.hex(24)
    session[:slack_oauth_state] = state
    redirect_to SlackSignInService.authorize_url(redirect_uri: callback_slack_account_url, state:, nonce:), allow_other_host: true
  end

  def callback
    expected_state = session.delete(:slack_oauth_state)

    if params[:error].present?
      flash[:info] = t(".cancelled")
      return redirect_to slack_account_path
    end

    unless expected_state.present? && ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
      flash[:error] = t(".invalid_state")
      return redirect_to slack_account_path
    end

    user = SlackSignInService.fetch_user(code: params[:code].to_s, redirect_uri: callback_slack_account_url)
    slack_id = user[:id]

    if Identity.where.not(id: current_identity.id).exists?(slack_id:)
      flash[:error] = t(".already_linked")
      return redirect_to slack_account_path
    end

    if current_identity.update(slack_id:)
      current_identity.create_activity :link_slack, owner: current_identity, recipient: current_identity
      if (url = return_url)
        return redirect_to url, allow_other_host: true
      end
      flash[:success] = t(".success", name: user[:name].presence || slack_id)
    else
      flash[:error] = current_identity.errors.full_messages.to_sentence
    end
    redirect_to slack_account_path
  rescue SlackSignInService::WrongWorkspace
    flash[:error] = t(".wrong_workspace")
    redirect_to slack_account_path
  rescue SlackSignInService::Error, HTTP::Error, JSON::ParserError => e
    Rails.logger.error "Slack linking failed for identity #{current_identity.id}: #{e.message}"
    flash[:error] = t(".failed")
    redirect_to slack_account_path
  end

  private

  def return_url = session.delete(:slack_link_return_to)
end
