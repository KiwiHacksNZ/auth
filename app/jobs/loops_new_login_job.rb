class LoopsNewLoginJob < ApplicationJob
  queue_as :default

  def perform(identity_session_id)
    session = IdentitySession.find(identity_session_id)
    identity = session.identity

    device_description = [
      session.device_info.present? ? "on #{session.device_info}" : nil,
      session.os_info.present? ? "running #{session.os_info}" : nil
    ].compact.join(" ")

    LoopsService.send_transactional(
      template: :new_login,
      email: identity.primary_email,
      data_variables: {
        userFirstName: identity.first_name,
        deviceInfo: device_description,
        ipAddress: session.ip.presence || "Unknown"
      }
    )
  end
end
