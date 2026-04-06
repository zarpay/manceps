# frozen_string_literal: true

module Manceps
  module Auth
    # No-op auth strategy for unauthenticated connections.
    class None
      def apply(headers)
        # no-op
      end
    end
  end
end
