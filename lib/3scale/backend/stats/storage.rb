require_relative '../storage'
require_relative 'keys'
require '3scale/backend/analytics/kinesis/adapter'
require '3scale/backend/stats/bucket_reader'
require '3scale/backend/stats/bucket_storage'
require '3scale/backend/stats/stats_parser'

module ThreeScale
  module Backend
    module Stats
      class Storage

        STATS_ENABLED_KEY = 'stats:enabled'.freeze
        private_constant :STATS_ENABLED_KEY

        DISABLED_BECAUSE_EMERGENCY_KEY = 'stats:disabled_emergency'.freeze
        private_constant :DISABLED_BECAUSE_EMERGENCY_KEY

        class << self
          include Memoizer::Decorator

          def enabled?
            storage.get(STATS_ENABLED_KEY).to_i == 1
          end
          memoize :enabled?

          def enable!
            storage.set(STATS_ENABLED_KEY, '1')
          end

          # Bucket storage can be disabled because an 'emergency' happened.
          # If too many buckets accumulate, we disable the feature because
          # the memory occupied by Redis can grow very quickly.
          # Check the code in the Aggregator class to check the conditions
          # that trigger this 'emergency'.
          def disable!(emergency = false)
            storage.del(STATS_ENABLED_KEY)

            if emergency
              storage.set(DISABLED_BECAUSE_EMERGENCY_KEY, '1')
            else
              storage.del(DISABLED_BECAUSE_EMERGENCY_KEY)
            end
          end

          # Returns whether the last time that bucket storage was disabled was
          # because of an emergency. Notice that this method can return 'true'
          # even when enabled? is true.
          def last_disable_was_emergency?
            storage.get(DISABLED_BECAUSE_EMERGENCY_KEY).to_i == 1
          end
          memoize :last_disable_was_emergency?

          def bucket_storage
            @bucket_storage ||= BucketStorage.new(stats_storage)
          end

          def bucket_reader
            @bucket_reader ||= BucketReader.new(config.stats.bucket_size,
                                                bucket_storage,
                                                storage)
          end

          def kinesis_adapter
            @kinesis_adapter ||= Analytics::Kinesis::Adapter.new(
              config.kinesis_stream_name,
              kinesis_client,
              stats_storage
            )
          end

          private

          def storage
            Backend::Storage.instance
          end

          # This is a separate storage used only for the analytics system. More
          # specifically, the only things saved in this storage are:
          #   - The buckets handled by the BucketStorage class.
          #   - The batches of events created by the Kinesis::Adapter class.
          def stats_storage
            @stats_storage ||= if config.analytics_redis && config.analytics_redis[:server]
                                 stats_storage_from_config
                               else
                                 # A stats storage has not been specified, so
                                 # use the same one for everything.
                                 storage
                               end
          end

          def stats_storage_from_config
            options = Backend::Storage::Helpers.config_with(config.analytics_redis)

            Redis.new(options)
          end

          def config
            Backend.configuration
          end

          def kinesis_client
            @kinesis_client ||= Aws::Firehose::Client.new(
                region: config.kinesis_region,
                access_key_id: config.aws_access_key_id,
                secret_access_key: config.aws_secret_access_key)
          end
        end

      end
    end
  end
end
