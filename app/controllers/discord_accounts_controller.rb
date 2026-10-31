class DiscordAccountsController < ApplicationController
  # Apps that send people here with ?source= to link Discord, and where to send them back.
  # A fixed list rather than a return_to URL, so this can't be used as an open redirect.
  RETURN_TO = {
    "mclink" => "https://mc.kiwihacks.com/link/resume"
  }.freeze

  def show
    @identity = current_identity
    session[:discord_link_source] = params[:source].presence_in(RETURN_TO.keys)

    if @identity.discord_id.present? && (url = return_url)
      redirect_to url, allow_other_host: true
    end
  end

  def create
    return redirect_to(discord_account_path) unless DiscordService.configured?

    state = SecureRandom.hex(24)
    session[:discord_oauth_state] = state
    redirect_to DiscordService.authorize_url(redirect_uri: callback_discord_account_url, state:), allow_other_host: true
  end

  def callback
    expected_state = session.delete(:discord_oauth_state)

    if params[:error].present?
      flash[:info] = t(".cancelled")
      return redirect_to discord_account_path
    end

    unless expected_state.present? && ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
      flash[:error] = t(".invalid_state")
      return redirect_to discord_account_path
    end

    user = DiscordService.fetch_user(code: params[:code].to_s, redirect_uri: callback_discord_account_url)
    discord_id = user["id"].to_s

    if Identity.where.not(id: current_identity.id).exists?(discord_id:)
      flash[:error] = t(".already_linked")
      return redirect_to discord_account_path
    end

    if current_identity.update(discord_id:)
      current_identity.create_activity :link_discord, owner: current_identity, recipient: current_identity
      if (url = return_url)
        return redirect_to url, allow_other_host: true
      end
      flash[:success] = t(".success", username: user["global_name"].presence || user["username"])
    else
      flash[:error] = current_identity.errors.full_messages.to_sentence
    end
    redirect_to discord_account_path
  rescue DiscordService::Error, HTTP::Error, JSON::ParserError => e
    Rails.logger.error "Discord linking failed for identity #{current_identity.id}: #{e.message}"
    flash[:error] = t(".failed")
    redirect_to discord_account_path
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

  def return_url = RETURN_TO[session.delete(:discord_link_source)]
end
