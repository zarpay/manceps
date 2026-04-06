# frozen_string_literal: true

module Manceps
  module Auth
    # Authenticates requests with a custom API key header.
    class ApiKeyHeader
      def initialize(header_name, key)
        @header_name = header_name.downcase
        @key = key
      end

      def apply(headers)
        headers[@header_name] = @key
      end
    end
  end
end
