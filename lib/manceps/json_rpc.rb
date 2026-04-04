require "json"

module Manceps
  module JsonRpc
    module_function

    def request(id, method, params = {})
      {jsonrpc: "2.0", id: id, method: method, params: params}
    end

    def notification(method, params = {})
      {jsonrpc: "2.0", method: method, params: params}
    end

    def initialize_request(id, client_info: nil, capabilities: {})
      config = Manceps.configuration
      info = client_info || {name: config.client_name, version: config.client_version}
      info[:description] = config.client_description if config.client_description

      request(id, "initialize", {
        protocolVersion: config.protocol_version,
        capabilities: capabilities,
        clientInfo: info
      })
    end

    def response(id, result)
      {jsonrpc: "2.0", id: id, result: result}
    end

    def initialized_notification
      notification("notifications/initialized")
    end

    def parse_response(data)
      data = JSON.parse(data, symbolize_names: true) if data.is_a?(String)

      unless data[:jsonrpc] == "2.0"
        raise ProtocolError.new("Invalid JSON-RPC version: #{data[:jsonrpc]}")
      end

      if data[:error]
        err = data[:error]
        raise ProtocolError.new(
          err[:message] || "Unknown error",
          code: err[:code],
          data: err[:data]
        )
      end

      data
    end
  end
end
