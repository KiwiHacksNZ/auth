class Portal::DiscordAccountsController < Portal::BaseController
  def portal
    @identity = current_identity
    return redirect_to_portal_return(status: :linked) if @identity.discord_id.present?

    # The link button posts with portal=1, and DiscordAccountsController#callback
    # sends people back here once Discord is linked, which returns them to their app.
  end

  def cancel = cancel_portal_flow
end
