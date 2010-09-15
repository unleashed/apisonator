module ThreeScale
  module Backend
    module Validators
      class Key < Base
        def apply
          if application.has_no_keys? || application.has_key?(params[:app_key])
            succeed!
          else
            fail!(ApplicationKeyInvalid.new(params[:app_key]))
          end
        end
      end
    end
  end
end
