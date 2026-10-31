class Portal::DiscordAccountsController < Portal::BaseController
  def portal
    @identity = current_identity

    if @identity.discord_id.present?
      session.delete(:discord_link_portal)
      return redirect_to_portal_return(status: :linked)
    end

    # Linking finishes in DiscordAccountsController#callback, which sends people back here.
    session[:discord_link_portal] = true
  end

  def cancel
    session.delete(:discord_link_portal)
    cancel_portal_flow
  end
end
