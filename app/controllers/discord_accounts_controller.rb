class DiscordAccountsController < ApplicationController
  include ProgramReturnUrl
  include SafeUrlValidation

  # Older ?source= shortcuts, kept so existing links keep working. New apps pass
  # ?return_to= with a URL on one of their official redirect URI hosts instead.
  # A same-site path (e.g. an /oauth/authorize request waiting on Discord) is
  # accepted too.
  # mclink is the KiwiHacks Link Velocity plugin, which resumes sign-in at /login/resume.
  SOURCES = {
    "mclink" => "https://play.kiwihacks.com/login/resume"
  }.freeze

  def show
    @identity = current_identity
    session[:discord_link_return_to] = url_from(params[:return_to]) || validated_return_url || SOURCES[params[:source]]

    if @identity.discord_id.present? && (url = return_url)
      redirect_to url, allow_other_host: true
    end
  end

  def create
    # ?portal=1 comes from the /portal/discord page. It's kept only for this one round
    # trip to Discord, so someone who leaves the portal page isn't sent back to it later.
    @from_portal = params[:portal].present?
    return redirect_to(link_page_path) unless DiscordService.configured?

    state = SecureRandom.hex(24)
    session[:discord_oauth_state] = state
    session[:discord_link_portal] = @from_portal
    redirect_to DiscordService.authorize_url(redirect_uri: callback_discord_account_url, state:), allow_other_host: true
  end

  def callback
    expected_state = session.delete(:discord_oauth_state)
    @from_portal = session.delete(:discord_link_portal)

    if params[:error].present?
      flash[:info] = t(".cancelled")
      return redirect_to link_page_path
    end

    unless expected_state.present? && ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
      flash[:error] = t(".invalid_state")
      return redirect_to link_page_path
    end

    user = DiscordService.fetch_user(code: params[:code].to_s, redirect_uri: callback_discord_account_url)
    discord_id = user["id"].to_s

    if Identity.where.not(id: current_identity.id).exists?(discord_id:)
      flash[:error] = t(".already_linked")
      return redirect_to link_page_path
    end

    if current_identity.update(discord_id:)
      current_identity.create_activity :link_discord, owner: current_identity, recipient: current_identity
      # The portal page sends people back to their app now that Discord is linked.
      return redirect_to portal_discord_path if @from_portal
      if (url = return_url)
        return redirect_to url, allow_other_host: true
      end
      flash[:success] = t(".success", username: user["global_name"].presence || user["username"])
    else
      flash[:error] = current_identity.errors.full_messages.to_sentence
    end
    redirect_to link_page_path
  rescue DiscordService::Error, HTTP::Error, JSON::ParserError => e
    Rails.logger.error "Discord linking failed for identity #{current_identity.id}: #{e.message}"
    flash[:error] = t(".failed")
    redirect_to link_page_path
  end

  def destroy
    if current_identity.discord_id.present?
      current_identity.update!(discord_id: nil)
      current_identity.create_activity :unlink_discord, owner: current_identity, recipient: current_identity
      flash[:success] = t(".success")
    end
    redirect_to discord_account_path
  end

  private

  def return_url = session.delete(:discord_link_return_to)

  def link_page_path = @from_portal ? portal_discord_path : discord_account_path
end
