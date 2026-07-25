class LoopsService
  BASE_URL = "https://app.loops.so/api/v1/transactional"

  TRANSACTIONAL_IDS = {
    login_code: ENV["LOOPS_TEMPLATE_LOGIN_CODE"],
    new_login: ENV["LOOPS_TEMPLATE_NEW_LOGIN"],
    backup_code_used: ENV["LOOPS_TEMPLATE_BACKUP_CODE_USED"],
    backup_codes_regenerated: ENV["LOOPS_TEMPLATE_BACKUP_CODES_REGENERATED"],
    two_factor_required_enabled: ENV["LOOPS_TEMPLATE_2FA_REQUIRED_ENABLED"],
    two_factor_required_disabled: ENV["LOOPS_TEMPLATE_2FA_REQUIRED_DISABLED"],
    two_factor_method_enabled: ENV["LOOPS_TEMPLATE_2FA_METHOD_ENABLED"],
    two_factor_method_disabled: ENV["LOOPS_TEMPLATE_2FA_METHOD_DISABLED"]
  }.freeze

  def self.send_transactional(template:, email:, data_variables: {})
    transactional_id = TRANSACTIONAL_IDS.fetch(template)
    raise "No Loops transactionalId configured for #{template}" if transactional_id.blank?

    response = HTTP.auth("Bearer #{ENV["LOOPS_API_KEY"]}")
      .post(BASE_URL, json: {
        transactionalId: transactional_id,
        email: email,
        dataVariables: data_variables
      })

    unless response.status.success?
      Rails.logger.error "Loops send failed (#{template}): #{response.status} #{response.body}"
    end

    response
  end
end
