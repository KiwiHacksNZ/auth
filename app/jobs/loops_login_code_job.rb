class LoopsLoginCodeJob < ApplicationJob
  queue_as :default

  def perform(login_code_id)
    login_code = Identity::V2LoginCode.find(login_code_id)
    identity = login_code.identity

    LoopsService.send_transactional(
      template: :login_code,
      email: identity.primary_email,
      data_variables: {
        userFirstName: identity.first_name,
        code: login_code.pretty
      }
    )
  end
end
