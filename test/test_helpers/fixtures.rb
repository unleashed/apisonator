module TestHelpers
  module Fixtures
    include ThreeScale
    include ThreeScale::Backend

    def self.included(base)
      base.send(:include, TestHelpers::Sequences)
    end

    private

    def setup_master_fixtures
      @master_service_id = ThreeScale::Backend.configuration.master_service_id.to_s

      @master_hits_id         = next_id
      @master_authorizes_id   = next_id
      @master_transactions_id = next_id
      @master_provider_key    = "master_provider_key_#{next_id}"

      Metric.save(
        :service_id => @master_service_id, :id => @master_hits_id, :name => 'hits',
        :children => [
          Metric.new(:id => @master_authorizes_id, :name => 'transactions/authorize')])

      Metric.save(
        :service_id => @master_service_id, :id => @master_transactions_id,
        :name => 'transactions')

      Service.save!(:provider_key => @master_provider_key, :id => @master_service_id)

      @master_plan_id = next_id
    end

    def setup_provider_fixtures
      setup_master_fixtures unless @master_service_id

      @provider_application_id = next_id
      @provider_key = "provider_key#{@provider_application_id}"

      Application.save(:service_id => @master_service_id,
                       :id         => @provider_application_id,
                       :state      => :active,
                       :plan_id    => @master_plan_id)

      Application.save_id_by_key(@master_service_id,
                                 @provider_key,
                                 @provider_application_id)

      @service_id = next_id
      @service = Service.save!(:provider_key => @provider_key, :id => @service_id)

      @plan_id = next_id
      @plan_name = "plan#{@plan_id}"
    end

    def setup_provider_fixtures_multiple_services
      setup_master_fixtures unless @master_service_id

      @provider_application_id = next_id
      @provider_key = "provider_key#{@provider_application_id}"

      Application.save(:service_id => @master_service_id,
                       :id         => @provider_application_id,
                       :state      => :active,
                       :plan_id    => @master_plan_id)

      Application.save_id_by_key(@master_service_id,
                                 @provider_key,
                                 @provider_application_id)

      service_id = next_id
      @service_1 = Service.save!(:provider_key => @provider_key, :id => service_id)

      service_id = next_id
      @service_2 = Service.save!(:provider_key => @provider_key, :id => service_id)

      service_id = next_id
      @service_3 = Service.save!(:provider_key => @provider_key, :id => service_id)

      @plan_id_1 = next_id
      @plan_name_1 = "plan#{@plan_id_1}"

      @plan_id_2 = next_id
      @plan_name_2 = "plan#{@plan_id_2}"

      @plan_id_3 = next_id
      @plan_name_3 = "plan#{@plan_id_3}"
    end

    def setup_oauth_provider_fixtures
      setup_provider_fixtures
      @service = Service.save!(provider_key: @provider_key, id: @service_id, backend_version: 'oauth')
    end

    def setup_oauth_provider_fixtures_multiple_services
      setup_provider_fixtures_multiple_services
      @service_1 = Service.save!(:provider_key => @provider_key, :id => @service_1.id, backend_version: 'oauth')
      @service_2 = Service.save!(:provider_key => @provider_key, :id => @service_2.id, backend_version: 'oauth')
      @service_3 = Service.save!(:provider_key => @provider_key, :id => @service_3.id, backend_version: 'oauth')
    end

    def seed_data
      #MASTER_SERVICE_ID = 1
      ## for the master
      master_service_id = ThreeScale::Backend.configuration.master_service_id
      Metric.save(
        service_id: master_service_id,
        id:         100,
        name:       'hits',
        children:   [
          Metric.new(id: 102, name: 'transactions/authorize')
        ])

      Metric.save(
        service_id: master_service_id,
        id:         200,
        name:       'transactions'
      )

      ## for the provider
      provider_key = "provider_key"
      metrics      = []

      2.times do |i|
        i += 1
        service_id = 1000 + i
        Service.save!(provider_key: provider_key, id: service_id)
        Application.save(service_id: service_id, id: 2000 + i, state: :live)
        metrics << Metric.save(service_id: service_id, id: 3000 + i, name: 'hits')
      end
      @metric_hits = metrics.first
    end

    def default_transaction_timestamp
      Time.utc(2010, 5, 7, 13, 23, 33)
    end

    def default_transaction_attrs
      {
        service_id:     1001,
        application_id: 2001,
        timestamp:      default_transaction_timestamp,
        usage:          { '3001' => 1 },
      }
    end

    def default_transaction attrs = {}
      Transaction.new default_transaction_attrs.merge(attrs)
    end

    def transaction_with_set_value
      default_transaction usage: { '3001' => '#665' }
    end

    def transaction_with_response_code code = 200
      default_transaction response_code: code
    end

    def setup_provider_without_default_service
      @provider_key_without_default_service = next_id

      service1 = Service.save!(provider_key: @provider_key_without_default_service,
                              id: next_id)

      Service.save!(provider_key: @provider_key_without_default_service,
                    id: next_id)

      # Delete the default service. The provider will have just 1 non-default service.
      Service.load_by_id(service1.id).tap do |service|
        service.delete_data
        service.clear_cache
      end
    end

    # Given a service and a metric ID, creates a user and an app for that
    # service and creates usage limits with different max for both.
    # Returns a hash with 2 keys: :user, and :app.
    # Side effect: modifies the given service so we can register users
    def limited_app_and_user!(service, metric_id, app_daily_limit, user_daily_limit)
      # Set up the service so we can register users
      service.user_registration_required = false
      service.default_user_plan_name = 'default_user_plan'
      service.default_user_plan_id = next_id
      service.save!

      # Set up the app and its limits
      app_plan_id = next_id
      UsageLimit.save(service_id: service.id,
                      plan_id: app_plan_id,
                      metric_id: metric_id,
                      day: app_daily_limit)
      app = Application.save(service_id: service.id,
                             id: next_id,
                             state: :active,
                             plan_id: app_plan_id,
                             user_required: true)

      # Set up the user and its limits
      user_plan_id = next_id
      UsageLimit.save(service_id: service.id,
                      plan_id: user_plan_id,
                      metric_id: metric_id,
                      day: user_daily_limit)
      user = User.new(service_id: service.id,
                      username: 'Bob',
                      state: :active,
                      plan_id: user_plan_id)
      user.save

      { app: app, user: user }
    end
  end
end
