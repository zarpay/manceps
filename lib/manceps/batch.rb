module Manceps
  class Batch
    attr_reader :requests, :results

    def initialize(client)
      @client = client
      @requests = []
      @results = {}
    end

    # Queue a tool call
    def call_tool(name, **arguments)
      id = @client.session.next_id
      @requests << { id: id, body: JsonRpc.request(id, "tools/call", { name: name, arguments: arguments }), type: :tool_call }
      id
    end

    # Queue a resource read
    def read_resource(uri)
      id = @client.session.next_id
      @requests << { id: id, body: JsonRpc.request(id, "resources/read", { uri: uri }), type: :resource_read }
      id
    end

    # Queue a prompt get
    def get_prompt(name, **arguments)
      id = @client.session.next_id
      @requests << { id: id, body: JsonRpc.request(id, "prompts/get", { name: name, arguments: arguments }), type: :prompt_get }
      id
    end

    # Execute all queued requests in a single batch
    def execute
      return {} if @requests.empty?

      batch_body = @requests.map { |r| r[:body] }
      responses = @client.send(:transport_batch_request, batch_body)

      # Correlate responses by id
      response_map = {}
      Array(responses).each do |resp|
        response_map[resp["id"]] = resp
      end

      @requests.each do |req|
        resp = response_map[req[:id]]
        next unless resp

        if resp["error"]
          @results[req[:id]] = ProtocolError.new(
            resp["error"]["message"] || "Unknown error",
            code: resp["error"]["code"],
            data: resp["error"]["data"]
          )
        else
          @results[req[:id]] = case req[:type]
          when :tool_call
            ToolResult.new(resp["result"])
          when :resource_read
            ResourceContents.new(resp["result"])
          when :prompt_get
            PromptResult.new(resp["result"])
          end
        end
      end

      @results
    end

    # Get result by request id
    def [](id)
      @results[id]
    end
  end
end
