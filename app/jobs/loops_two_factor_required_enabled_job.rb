class LoopsTwoFactorRequiredEnabledJob < ApplicationJob
  queue_as :default

  def perform(identity_id)
    identity = Identity.find(identity_id)

    LoopsService.send_transactional(
      template: :two_factor_required_enabled,
      email: identity.primary_email,
      data_variables: {
        userFirstName: identity.first_name
      }
    )
  end
end
