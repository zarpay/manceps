# frozen_string_literal: true

module Manceps
  module Auth
    class None
      def apply(headers)
        # no-op
      end
    end
  end
end
