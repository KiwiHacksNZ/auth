class LoopsBackupCodeUsedJob < ApplicationJob
  queue_as :default

  def perform(identity_id)
    identity = Identity.find(identity_id)

    LoopsService.send_transactional(
      template: :backup_code_used,
      email: identity.primary_email,
      data_variables: {
        userFirstName: identity.first_name
      }
    )
  end
end
