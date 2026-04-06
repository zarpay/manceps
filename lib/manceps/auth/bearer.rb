# frozen_string_literal: true

module Manceps
  module Auth
    class Bearer
      def initialize(token)
        @token = token
      end

      def apply(headers)
        headers['authorization'] = "Bearer #{@token}"
      end
    end
  end
end
