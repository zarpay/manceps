module Manceps
  class Session
    attr_reader :id, :capabilities, :protocol_version, :server_info

    def initialize
      reset
    end

    def next_id
      @request_counter += 1
    end

    def establish(response)
      result = response[:result] || {}
      @id = response[:session_id] || response[:sessionId]
      @capabilities = result[:capabilities] || {}
      @protocol_version = result[:protocolVersion]
      @server_info = result[:serverInfo]
    end

    def active?
      !@id.nil?
    end

    def reset
      @id = nil
      @capabilities = {}
      @protocol_version = nil
      @server_info = nil
      @request_counter = 0
    end
  end
end
