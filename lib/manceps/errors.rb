# frozen_string_literal: true

module Manceps
  class Error < StandardError; end

  class ConnectionError < Error; end
  class TimeoutError < Error; end

  # JSON-RPC error from the MCP server.
  class ProtocolError < Error
    attr_reader :code, :data

    def initialize(message, code: nil, data: nil)
      @code = code
      @data = data
      super(message)
    end
  end

  class AuthenticationError < Error; end
  class SessionExpiredError < Error; end

  # Error raised when a tool invocation fails.
  class ToolError < Error
    attr_reader :result

    def initialize(message, result: nil)
      @result = result
      super(message)
    end
  end
end
