if ThreeScale::Backend.configuration.saas
  # SaaS-specific dependencies
  require '3scale/backend/log_request_storage'
  require '3scale/backend/log_request_cubert_storage'
  require '3scale/backend/transactor/log_request_job'
  require '3scale/backend/saas_stats'
end
