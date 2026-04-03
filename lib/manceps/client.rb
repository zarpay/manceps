module Manceps
  class Client
    attr_reader :session

    def initialize(url, auth: Auth::None.new, **options)
      @transport = Transport::StreamableHTTP.new(url, auth: auth, timeout: options[:timeout])
      @session = Session.new
    end

    def connect
      init_response = @transport.request(
        JsonRpc.initialize_request(@session.next_id)
      )
      handle_rpc_error(init_response)
      @session.establish(init_response)

      @transport.notify(JsonRpc.initialized_notification)
      self
    end

    def disconnect
      @transport.terminate_session(@session.id) if @session.active?
      @transport.close
      @session.reset
    end

    def connected?
      @session.active?
    end

    def tools
      paginate("tools/list", "tools") { |data| Tool.new(data) }
    end

    def call_tool(name, **arguments)
      response = request("tools/call", name: name, arguments: arguments)
      ToolResult.new(response["result"])
    end

    def self.open(url, **options)
      client = new(url, **options)
      client.connect
      yield client
    ensure
      client&.disconnect
    end

    private

    MAX_PAGES = 100

    def request(method, **params)
      body = JsonRpc.request(@session.next_id, method, params)
      response = @transport.request(body)
      handle_rpc_error(response)
      response
    end

    def paginate(method, items_key)
      results = []
      cursor = nil
      pages = 0

      loop do
        params = cursor ? { cursor: cursor } : {}
        response = request(method, **params)
        items = response.dig("result", items_key) || []
        results.concat(items.map { |data| yield(data) })

        cursor = response.dig("result", "nextCursor")
        pages += 1
        break if cursor.nil? || pages >= MAX_PAGES
      end

      results
    end

    def handle_rpc_error(response)
      return unless response.is_a?(Hash) && response["error"]

      error = response["error"]
      raise ProtocolError.new(
        error["message"] || "Unknown JSON-RPC error",
        code: error["code"],
        data: error["data"]
      )
    end
  end
end
