module Manceps
  class Client
    attr_reader :session

    def initialize(url_or_command, auth: Auth::None.new, args: nil, env: nil, max_retries: 3, **options)
      if args || !url_or_command.match?(/\Ahttps?:\/\//i)
        @transport = Transport::Stdio.new(url_or_command, args: args || [], env: env || {})
      else
        @transport = Transport::StreamableHTTP.new(url_or_command, auth: auth, timeout: options[:timeout])
      end
      @session = Session.new
      @max_retries = max_retries
      @backoff = Backoff.new
      @notification_handlers = Hash.new { |h, k| h[k] = [] }
      @elicitation_handler = nil
    end

    def connect
      attempts = 0
      begin
        @transport.open if @transport.respond_to?(:open)

        init_response = @transport.request(
          JsonRpc.initialize_request(@session.next_id, capabilities: client_capabilities)
        )
        handle_rpc_error(init_response)
        @session.establish(init_response)

        unless Manceps.configuration.supported_versions.include?(@session.protocol_version)
          server_version = @session.protocol_version
          disconnect
          raise ProtocolError.new(
            "Server negotiated unsupported protocol version: #{server_version}",
            code: -32600
          )
        end

        if @transport.respond_to?(:protocol_version=)
          @transport.protocol_version = @session.protocol_version
        end

        @transport.notify(JsonRpc.initialized_notification)
        @backoff.reset
        self
      rescue ConnectionError, TimeoutError => e
        attempts += 1
        @transport.close if @transport.respond_to?(:close)
        @session.reset
        raise if attempts > @max_retries
        sleep @backoff.next_delay
        retry
      end
    end

    def disconnect
      sid = @transport.respond_to?(:session_id) ? @transport.session_id : @session.id
      @transport.terminate_session(sid) if sid
      @transport.close
      @session.reset
    end

    def connected?
      @session.active?
    end

    def reconnect!
      @transport.close
      @session.reset
      connect
    end

    def ping
      @transport.notify(JsonRpc.notification("ping"))
      true
    rescue ConnectionError, TimeoutError
      false
    end

    def tools(force: false)
      paginate_with_retry("tools/list", "tools") { |data| Tool.new(data) }
    end

    def call_tool(name, **arguments)
      response = request_with_retry("tools/call", name: name, arguments: arguments)
      ToolResult.new(response["result"])
    end

    def call_tool_streaming(name, **arguments, &block)
      body = JsonRpc.request(@session.next_id, "tools/call", { name: name, arguments: arguments })
      wrapped_block = if block
        proc do |event|
          if event.is_a?(Hash) && event["id"] && event["method"]
            handle_server_request(event)
          else
            block.call(event)
          end
        end
      end
      response = @transport.request_streaming(body, &wrapped_block)
      handle_rpc_error(response)
      ToolResult.new(response["result"])
    end

    def prompts(force: false)
      paginate_with_retry("prompts/list", "prompts") { |data| Prompt.new(data) }
    end

    def get_prompt(name, **arguments)
      response = request_with_retry("prompts/get", name: name, arguments: arguments)
      PromptResult.new(response["result"])
    end

    def resources(force: false)
      paginate_with_retry("resources/list", "resources") { |data| Resource.new(data) }
    end

    def resource_templates
      paginate_with_retry("resources/templates/list", "resourceTemplates") { |data| ResourceTemplate.new(data) }
    end

    def read_resource(uri)
      response = request_with_retry("resources/read", uri: uri)
      ResourceContents.new(response["result"])
    end

    def on(method, &block)
      @notification_handlers[method] << block
    end

    def subscribe_resource(uri)
      request("resources/subscribe", uri: uri)
    end

    def unsubscribe_resource(uri)
      request("resources/unsubscribe", uri: uri)
    end

    def cancel_request(request_id, reason: nil)
      params = { requestId: request_id }
      params[:reason] = reason if reason
      @transport.notify(JsonRpc.notification("notifications/cancelled", params))
    end

    def listen
      @transport.listen do |message|
        if message["id"] && message["method"]
          handle_server_request(message)
        else
          method = message["method"]
          params = message["params"]
          handlers = @notification_handlers[method]
          handlers.each { |h| h.call(params) } if handlers
        end
      end
    end

    def on_elicitation(&block)
      @elicitation_handler = block
    end

    # --- Tasks (experimental, protocol 2025-11-25) ---

    def tasks
      response = request("tasks/list")
      (response.dig("result", "tasks") || []).map { |data| Task.new(data) }
    end

    def get_task(task_id)
      response = request("tasks/get", taskId: task_id)
      Task.new(response["result"])
    end

    def cancel_task(task_id)
      request("tasks/cancel", taskId: task_id)
      true
    end

    def await_task(task_id, interval: 1, timeout: nil)
      deadline = timeout ? Time.now + timeout : nil

      loop do
        task = get_task(task_id)
        return task if task.done?

        if deadline && Time.now >= deadline
          raise TimeoutError, "Task #{task_id} did not complete within #{timeout} seconds"
        end

        sleep interval
      end
    end

    def self.open(url, **options)
      client = new(url, **options)
      client.connect
      yield client
    ensure
      client&.disconnect
    end

    private

    def client_capabilities
      caps = {}
      caps["elicitation"] = { "form" => {} } if @elicitation_handler
      caps
    end

    def handle_server_request(request_data)
      case request_data["method"]
      when "elicitation/create"
        return unless @elicitation_handler
        elicitation = Elicitation.new(request_data["params"])
        result = @elicitation_handler.call(elicitation)
        response = JsonRpc.response(request_data["id"], result)
        @transport.notify(response)
      end
    end

    MAX_PAGES = 100

    def request(method, **params)
      body = JsonRpc.request(@session.next_id, method, params)
      response = @transport.request(body)
      handle_rpc_error(response)
      response
    end

    def request_with_retry(method, **params)
      request(method, **params)
    rescue SessionExpiredError
      reconnect!
      request(method, **params)
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

    def paginate_with_retry(method, items_key, &block)
      paginate(method, items_key, &block)
    rescue SessionExpiredError
      reconnect!
      paginate(method, items_key, &block)
    end

    def handle_rpc_error(response)
      return unless response.is_a?(Hash)

      error = response["error"] || response[:error]
      return unless error

      raise ProtocolError.new(
        error["message"] || error[:message] || "Unknown JSON-RPC error",
        code: error["code"] || error[:code],
        data: error["data"] || error[:data]
      )
    end
  end
end
