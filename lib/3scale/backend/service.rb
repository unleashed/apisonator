module ThreeScale
  module Backend
    class Service
      include Storable

      # list of attributes to be fetched from storage
      ATTRIBUTES = %i[referrer_filters_required backend_version
                      user_registration_required default_user_plan_id
                      default_user_plan_name provider_key].freeze
      private_constant :ATTRIBUTES

      attr_accessor :provider_key, :id, :backend_version,
        :default_user_plan_id, :default_user_plan_name
      attr_writer :referrer_filters_required, :user_registration_required,
        :default_service

      class << self
        include Memoizer::Decorator

        def attribute_names
          (ATTRIBUTES + %i[id default_service].freeze).freeze
        end

        # Returns true if a given service belongs to the provider with
        # that key without loading the whole object.
        #
        def authenticate_service_id(service_id, provider_key)
          provider_key == provider_key_for(service_id)
        end
        memoize :authenticate_service_id

        def default_id(provider_key)
          storage.get(storage_key_by_provider(provider_key, :id))
        end
        memoize :default_id

        def default_id!(provider_key)
          default_id(provider_key) or raise ProviderKeyInvalid, provider_key
        end

        def load(provider_key)
          load_by_id default_id(provider_key)
        end
        memoize :load

        def load!(provider_key)
          load(provider_key) or raise ProviderKeyInvalid, provider_key
        end

        def load_by_id(service_id)
          return if service_id.nil?

          service_attrs = get_service(id = service_id.to_s)
          massage_service_attrs service_attrs

          return if service_attrs[:provider_key].nil?

          new(service_attrs.merge(id: id,
            default_service: default_service?(service_attrs[:provider_key], id)
          ))
        end
        memoize :load_by_id

        def load_by_id!(service_id)
          load_by_id(service_id) or raise ServiceIdInvalid, service_id
        end

        def load_with_provider_key!(id, provider_key)
          id = Service.default_id(provider_key) if id.nil? || id.empty?
          raise ProviderKeyInvalidOrServiceMissing, provider_key if id.nil? || id.empty?

          service = Service.load_by_id(id.split('-').last) || Service.load_by_id!(id)

          if service.provider_key != provider_key
            # this is an error; let's raise in default_id! or raise invalid service
            Service.default_id!(provider_key)
            raise ServiceIdInvalid, id
          end

          service
        end

        def delete_by_id(service_id)
          service = load_by_id!(service_id)
          raise ServiceIsDefaultService, service.id if service.default_service?

          service.delete_data
          service.clear_cache
        end

        def exists?(service_id)
          storage.exists(storage_key(service_id, 'provider_key'))
        end

        def get_service(id)
          keys = ATTRIBUTES.map { |attr| storage_key(id, attr) }
          values = storage.mget(keys)

          result = {}
          ATTRIBUTES.each_with_index do |key, idx|
            result[key] = values[idx]
          end
          result
        end

        def list(provider_key)
          storage.smembers(storage_key_by_provider(provider_key, :ids)) || []
        end
        memoize :list

        def save!(attributes = {})
          massage_set_user_registration_required attributes

          new(attributes).save!
        end

        def storage_key(id, attribute)
          encode_key("service/id:#{id}/#{attribute}")
        end

        def storage_key_by_provider(provider_key, attribute)
          encode_key("service/provider_key:#{provider_key}/#{attribute}")
        end

        def clear_cache(provider_key, id)
          provider_key_arg = [provider_key]
          keys = Memoizer.build_keys_for_class(self,
                    authenticate_service_id: [id, provider_key],
                    default_id: provider_key_arg,
                    load: provider_key_arg,
                    load_by_id: [id],
                    list: provider_key_arg,
                    provider_key_for: [id])
          Memoizer.clear keys
        end

        # Gets the provider key without loading the whole service
        def provider_key_for(service_id)
          storage.get(storage_key(service_id, 'provider_key'.freeze))
        end
        memoize :provider_key_for

        private

        def massage_service_attrs(service_attrs)
          service_attrs[:referrer_filters_required] =
            service_attrs[:referrer_filters_required].to_i > 0
          service_attrs[:user_registration_required] =
            massage_get_user_registration_required(
              service_attrs[:user_registration_required])

          service_attrs
        end

        # nil => true, 1 => true, '1' => true, 0 => false, '0' => false
        def massage_get_user_registration_required(value)
          value.nil? ? true : value.to_i > 0
        end

        def massage_set_user_registration_required(attributes)
          if attributes[:user_registration_required].nil?
            val = storage.get(storage_key(attributes[:id], :user_registration_required))
            attributes[:user_registration_required] =
              (!val.nil? && val.to_i == 0) ? false : true
          end
        end

        def get_attr(id, attribute)
          storage.get(storage_key(id, attribute))
        end

        def default_service?(provider_key, id)
          default_id(provider_key) == id.to_s
        end
      end

      def default_service?
        @default_service
      end

      def referrer_filters_required?
        @referrer_filters_required
      end

      def user_registration_required?
        @user_registration_required
      end

      def save!
        validate_user_registration_required
        set_as_default_if_needed
        persist
        clear_cache
        self
      end

      def clear_cache
        self.class.clear_cache(provider_key, id)
      end

      def storage_key(attribute)
        self.class.storage_key id, attribute
      end

      def delete_data
        delete_from_lists
        delete_attributes
      end

      def to_hash
        {
          id: id,
          provider_key: provider_key,
          backend_version: backend_version,
          referrer_filters_required: referrer_filters_required?,
          user_registration_required: user_registration_required?,
          default_user_plan_id: default_user_plan_id,
          default_user_plan_name: default_user_plan_name,
          default_service: default_service?
        }
      end

      private

      def delete_attributes
        keys = ATTRIBUTES.map { |attr| storage_key(attr) }
        keys << storage_key(:user_set)
        keys << storage_key_by_provider(:id) if default_service?
        storage.del keys
      end

      def delete_from_lists
        set = storage_key_by_provider :ids
        storage.srem set, id
        storage.srem encode_key('services_set'), id
        storage.del set if default_service?
      end

      def storage_key_by_provider(attribute)
        self.class.storage_key_by_provider provider_key, attribute
      end

      def validate_user_registration_required
        @user_registration_required = true if @user_registration_required.nil?

        if !user_registration_required? &&
          (default_user_plan_id.nil? || default_user_plan_name.nil?)
          raise ServiceRequiresDefaultUserPlan
        end
      end

      def set_as_default_if_needed
        if @default_service.nil?
          default_service_id = self.class.default_id(provider_key)
          @default_service = default_service_id.nil?
        end
      end

      def persist
        persist_default(self.class.default_id(provider_key)) if default_service?
        persist_attributes
        persist_sets
      end

      def persist_default(old_default_id)
        # we get all sorts of combinations of Strings and Fixnums here. Convert'em.
        if old_default_id.to_i != id.to_i
          storage.set storage_key_by_provider(:id), id
          # we should now clear memoizations of the previous default service
          self.class.clear_cache(provider_key, old_default_id)
        end
      end

      def persist_attributes
        persist_attribute :referrer_filters_required, referrer_filters_required? ? 1 : 0
        persist_attribute :user_registration_required, user_registration_required? ? 1 : 0
        persist_attribute :default_user_plan_id, default_user_plan_id, true
        persist_attribute :default_user_plan_name, default_user_plan_name, true
        persist_attribute :backend_version, backend_version, true
        persist_attribute :provider_key, provider_key
      end

      def persist_attribute(attribute, value, ignore_nils = false)
        storage.set storage_key(attribute), value unless ignore_nils && value.nil?
      end

      def persist_sets
        storage.sadd storage_key_by_provider(:ids), id
        storage.sadd encode_key("services_set"), id
        storage.sadd encode_key("provider_keys_set"), provider_key
      end

    end
  end
end
