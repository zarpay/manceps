require "spec_helper"

RSpec.describe Manceps::Client do
  let(:url) { "https://example.com/mcp" }
  let(:auth) { Manceps::Auth::Bearer.new("test-token") }

  # Shared stubs
  let(:init_response_body) do
    JSON.generate({
      jsonrpc: "2.0",
      id: 1,
      result: {
        protocolVersion: "2025-03-26",
        capabilities: { tools: {} },
        serverInfo: { name: "TestServer", version: "1.0" }
      }
    })
  end

  let(:init_response_headers) do
    { "Content-Type" => "application/json", "Mcp-Session-Id" => "test-session-123" }
  end

  def stub_initialize
    stub_request(:post, url)
      .with(
        body: hash_including("method" => "initialize"),
        headers: { "Authorization" => "Bearer test-token" }
      )
      .to_return(
        status: 200,
        headers: init_response_headers,
        body: init_response_body
      )
  end

  def stub_initialized_notification
    stub_request(:post, url)
      .with(body: hash_including("method" => "notifications/initialized"))
      .to_return(status: 202)
  end

  def stub_tools_list(tools: [], next_cursor: nil)
    result = { tools: tools }
    result[:nextCursor] = next_cursor if next_cursor

    stub_request(:post, url)
      .with(body: hash_including("method" => "tools/list"))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({ jsonrpc: "2.0", id: 2, result: result })
      )
  end

  def stub_tool_call(result_content)
    stub_request(:post, url)
      .with(body: hash_including("method" => "tools/call"))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          jsonrpc: "2.0", id: 2,
          result: { content: result_content, isError: false }
        })
      )
  end

  def stub_delete_session
    stub_request(:delete, url).to_return(status: 200)
  end

  describe "#connect" do
    it "sends initialize request followed by initialized notification" do
      init_stub = stub_initialize
      notif_stub = stub_initialized_notification

      client = described_class.new(url, auth: auth)
      client.connect

      expect(init_stub).to have_been_requested
      expect(notif_stub).to have_been_requested
    end

    it "returns self for chaining" do
      stub_initialize
      stub_initialized_notification

      client = described_class.new(url, auth: auth)
      result = client.connect

      expect(result).to be(client)
    end

    it "stores session info from server response" do
      stub_initialize
      stub_initialized_notification

      client = described_class.new(url, auth: auth)
      client.connect

      # The transport captures Mcp-Session-Id and sends it on subsequent
      # requests, verified by header assertions in other specs.
      expect(client.session).to be_a(Manceps::Session)
    end
  end

  describe "#tools" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "returns an array of Tool objects" do
      stub_tools_list(tools: [
        { name: "get_weather", description: "Get weather", inputSchema: { type: "object" } },
        { name: "search", description: "Search the web", inputSchema: { type: "object" } }
      ])

      client = described_class.new(url, auth: auth)
      client.connect
      tools = client.tools

      expect(tools.length).to eq(2)
      expect(tools).to all(be_a(Manceps::Tool))
      expect(tools.first.name).to eq("get_weather")
      expect(tools.first.description).to eq("Get weather")
      expect(tools.last.name).to eq("search")
    end

    it "returns empty array when server has no tools" do
      stub_tools_list(tools: [])

      client = described_class.new(url, auth: auth)
      client.connect

      expect(client.tools).to eq([])
    end
  end

  describe "#call_tool" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "sends tools/call and returns a ToolResult" do
      stub_tool_call([{ type: "text", text: "Sunny, 72F" }])

      client = described_class.new(url, auth: auth)
      client.connect
      result = client.call_tool("get_weather", location: "NYC")

      expect(result).to be_a(Manceps::ToolResult)
      expect(result.text).to eq("Sunny, 72F")
      expect(result.error?).to be false
    end

    it "includes tool arguments in the request" do
      call_stub = stub_request(:post, url)
        .with(body: hash_including(
          "method" => "tools/call",
          "params" => hash_including(
            "name" => "get_weather",
            "arguments" => { "location" => "NYC" }
          )
        ))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 2,
            result: { content: [{ type: "text", text: "ok" }], isError: false }
          })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      client.call_tool("get_weather", location: "NYC")

      expect(call_stub).to have_been_requested
    end
  end

  describe "#prompts" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "returns an array of Prompt objects" do
      stub_request(:post, url)
        .with(body: hash_including("method" => "prompts/list"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 2,
            result: {
              prompts: [
                { name: "code_review", description: "Review code", arguments: [{ name: "code", required: true }] },
                { name: "summarize", description: "Summarize text" }
              ]
            }
          })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      prompts = client.prompts

      expect(prompts.length).to eq(2)
      expect(prompts).to all(be_a(Manceps::Prompt))
      expect(prompts.first.name).to eq("code_review")
      expect(prompts.first.arguments.length).to eq(1)
      expect(prompts.last.name).to eq("summarize")
    end
  end

  describe "#get_prompt" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "sends prompts/get and returns a PromptResult" do
      stub_request(:post, url)
        .with(body: hash_including(
          "method" => "prompts/get",
          "params" => hash_including("name" => "code_review", "arguments" => { "code" => "puts 1" })
        ))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 2,
            result: {
              description: "Code review prompt",
              messages: [
                { role: "user", content: { type: "text", text: "Review: puts 1" } }
              ]
            }
          })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      result = client.get_prompt("code_review", code: "puts 1")

      expect(result).to be_a(Manceps::PromptResult)
      expect(result.description).to eq("Code review prompt")
      expect(result.messages.length).to eq(1)
      expect(result.messages.first.role).to eq("user")
      expect(result.messages.first.text).to eq("Review: puts 1")
    end
  end

  describe "#call_tool_streaming" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "yields intermediate events and returns a ToolResult" do
      sse_body = <<~SSE
        event: progress
        data: {"type":"progress","progress":50}

        event: message
        data: {"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"done"}],"isError":false}}
      SSE

      stub_request(:post, url)
        .with(body: hash_including("method" => "tools/call"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: sse_body
        )

      client = described_class.new(url, auth: auth)
      client.connect

      yielded_events = []
      result = client.call_tool_streaming("slow_tool", input: "data") { |e| yielded_events << e }

      expect(result).to be_a(Manceps::ToolResult)
      expect(result.text).to eq("done")
      expect(yielded_events.length).to eq(1)
      expect(yielded_events[0]["type"]).to eq("progress")
    end
  end

  describe "#disconnect" do
    it "calls close on the transport and resets the session" do
      stub_initialize
      stub_initialized_notification
      stub_delete_session

      client = described_class.new(url, auth: auth)
      client.connect
      client.disconnect

      expect(client.session.active?).to be false
    end
  end

  describe ".open" do
    it "connects, yields the client, and disconnects" do
      stub_initialize
      stub_initialized_notification
      stub_tools_list(tools: [
        { name: "echo", description: "Echo input", inputSchema: { type: "object" } }
      ])
      stub_delete_session

      yielded_client = nil

      described_class.open(url, auth: auth) do |client|
        yielded_client = client
        expect(client.tools.length).to eq(1)
      end

      expect(yielded_client).to be_a(described_class)
      expect(yielded_client.session.active?).to be false
    end

    it "disconnects even when block raises" do
      stub_initialize
      stub_initialized_notification
      stub_delete_session

      client_ref = nil

      expect {
        described_class.open(url, auth: auth) do |client|
          client_ref = client
          raise "boom"
        end
      }.to raise_error(RuntimeError, "boom")

      expect(client_ref.session.active?).to be false
    end
  end

  describe "JSON-RPC error handling" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "raises ProtocolError when server returns a JSON-RPC error" do
      stub_request(:post, url)
        .with(body: hash_including("method" => "tools/list"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 2,
            error: { code: -32601, message: "Method not found" }
          })
        )

      client = described_class.new(url, auth: auth)
      client.connect

      expect { client.tools }.to raise_error(Manceps::ProtocolError) do |err|
        expect(err.message).to eq("Method not found")
        expect(err.code).to eq(-32601)
      end
    end

    it "raises ProtocolError when initialize itself returns an error" do
      # Override the default init stub for this test
      WebMock.reset!

      stub_request(:post, url)
        .with(body: hash_including("method" => "initialize"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 1,
            error: { code: -32600, message: "Invalid protocol version" }
          })
        )

      client = described_class.new(url, auth: auth)

      expect { client.connect }.to raise_error(Manceps::ProtocolError, "Invalid protocol version")
    end
  end

  describe "#resources" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "returns an array of Resource objects" do
      stub_request(:post, url)
        .with(body: hash_including("method" => "resources/list"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 2,
            result: {
              resources: [
                { uri: "file:///readme.md", name: "README", description: "Project readme", mimeType: "text/markdown" },
                { uri: "file:///config.json", name: "Config", description: "App config" }
              ]
            }
          })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      resources = client.resources

      expect(resources.length).to eq(2)
      expect(resources).to all(be_a(Manceps::Resource))
      expect(resources.first.uri).to eq("file:///readme.md")
      expect(resources.first.name).to eq("README")
      expect(resources.first.mime_type).to eq("text/markdown")
      expect(resources.last.uri).to eq("file:///config.json")
    end

    it "returns empty array when server has no resources" do
      stub_request(:post, url)
        .with(body: hash_including("method" => "resources/list"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 2, result: { resources: [] } })
        )

      client = described_class.new(url, auth: auth)
      client.connect

      expect(client.resources).to eq([])
    end
  end

  describe "#resource_templates" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "returns an array of ResourceTemplate objects" do
      stub_request(:post, url)
        .with(body: hash_including("method" => "resources/templates/list"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 2,
            result: {
              resourceTemplates: [
                { uriTemplate: "file:///logs/{date}.log", name: "Daily Log", description: "Logs by date" }
              ]
            }
          })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      templates = client.resource_templates

      expect(templates.length).to eq(1)
      expect(templates.first).to be_a(Manceps::ResourceTemplate)
      expect(templates.first.uri_template).to eq("file:///logs/{date}.log")
      expect(templates.first.name).to eq("Daily Log")
    end
  end

  describe "#read_resource" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "sends resources/read and returns ResourceContents" do
      stub_request(:post, url)
        .with(body: hash_including(
          "method" => "resources/read",
          "params" => hash_including("uri" => "file:///readme.md")
        ))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 2,
            result: {
              contents: [
                { type: "text", text: "# Hello\nWelcome to the project", uri: "file:///readme.md", mimeType: "text/markdown" }
              ]
            }
          })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      result = client.read_resource("file:///readme.md")

      expect(result).to be_a(Manceps::ResourceContents)
      expect(result.contents.length).to eq(1)
      expect(result.text).to eq("# Hello\nWelcome to the project")
    end
  end

  describe "#on" do
    it "registers notification handlers" do
      client = described_class.new(url, auth: auth)
      received = []
      client.on("notifications/tools/list_changed") { |params| received << params }

      handlers = client.instance_variable_get(:@notification_handlers)
      expect(handlers["notifications/tools/list_changed"].length).to eq(1)
    end

    it "allows multiple handlers for the same notification" do
      client = described_class.new(url, auth: auth)
      client.on("notifications/tools/list_changed") { }
      client.on("notifications/tools/list_changed") { }

      handlers = client.instance_variable_get(:@notification_handlers)
      expect(handlers["notifications/tools/list_changed"].length).to eq(2)
    end
  end

  describe "#subscribe_resource" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "sends resources/subscribe with the URI" do
      sub_stub = stub_request(:post, url)
        .with(body: hash_including(
          "method" => "resources/subscribe",
          "params" => hash_including("uri" => "file:///readme.md")
        ))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 3, result: {} })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      client.subscribe_resource("file:///readme.md")

      expect(sub_stub).to have_been_requested
    end
  end

  describe "#unsubscribe_resource" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "sends resources/unsubscribe with the URI" do
      unsub_stub = stub_request(:post, url)
        .with(body: hash_including(
          "method" => "resources/unsubscribe",
          "params" => hash_including("uri" => "file:///readme.md")
        ))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 3, result: {} })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      client.unsubscribe_resource("file:///readme.md")

      expect(unsub_stub).to have_been_requested
    end
  end

  describe "#cancel_request" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "sends notifications/cancelled with the request ID" do
      cancel_stub = stub_request(:post, url)
        .with(body: hash_including(
          "method" => "notifications/cancelled",
          "params" => hash_including("requestId" => 42)
        ))
        .to_return(status: 202)

      client = described_class.new(url, auth: auth)
      client.connect
      client.cancel_request(42)

      expect(cancel_stub).to have_been_requested
    end

    it "includes reason when provided" do
      cancel_stub = stub_request(:post, url)
        .with(body: hash_including(
          "method" => "notifications/cancelled",
          "params" => hash_including("requestId" => 42, "reason" => "User cancelled")
        ))
        .to_return(status: 202)

      client = described_class.new(url, auth: auth)
      client.connect
      client.cancel_request(42, reason: "User cancelled")

      expect(cancel_stub).to have_been_requested
    end
  end

  describe "#listen" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "dispatches notifications to registered handlers" do
      sse_body = <<~SSE
        event: message
        data: {"jsonrpc":"2.0","method":"notifications/tools/list_changed","params":{}}

        event: message
        data: {"jsonrpc":"2.0","method":"notifications/resources/updated","params":{"uri":"file:///config.json"}}
      SSE

      stub_request(:get, url)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: sse_body
        )

      client = described_class.new(url, auth: auth)
      client.connect

      tools_changed = []
      resources_updated = []
      client.on("notifications/tools/list_changed") { |params| tools_changed << params }
      client.on("notifications/resources/updated") { |params| resources_updated << params }

      client.listen

      expect(tools_changed.length).to eq(1)
      expect(resources_updated.length).to eq(1)
      expect(resources_updated.first).to eq({ "uri" => "file:///config.json" })
    end
  end

  describe "#tools with force:" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "accepts force: true parameter" do
      stub_tools_list(tools: [])

      client = described_class.new(url, auth: auth)
      client.connect

      expect { client.tools(force: true) }.not_to raise_error
    end
  end

  describe "#reconnect!" do
    before do
      stub_initialized_notification
    end

    it "closes transport, resets session, and re-initializes" do
      init_stub = stub_initialize

      client = described_class.new(url, auth: auth)
      client.connect

      # reconnect! should close, reset, and re-connect
      client.reconnect!

      # initialize should have been called twice (once for connect, once for reconnect)
      expect(init_stub).to have_been_requested.times(2)
    end

    it "resets the session request counter" do
      stub_initialize

      client = described_class.new(url, auth: auth)
      client.connect

      # Advance the counter
      3.times { client.session.next_id }

      client.reconnect!

      # After reconnect, counter should have been reset (1 used by connect's init request)
      expect(client.session.next_id).to eq(2)
    end
  end

  describe "#ping" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "returns true on success" do
      stub_request(:post, url)
        .with(body: hash_including("method" => "ping"))
        .to_return(status: 202)

      client = described_class.new(url, auth: auth)
      client.connect

      expect(client.ping).to be true
    end

    it "returns false on ConnectionError" do
      client = described_class.new(url, auth: auth)
      client.connect

      transport = client.instance_variable_get(:@transport)
      allow(transport).to receive(:notify).and_raise(Manceps::ConnectionError, "gone")

      expect(client.ping).to be false
    end

    it "returns false on TimeoutError" do
      client = described_class.new(url, auth: auth)
      client.connect

      transport = client.instance_variable_get(:@transport)
      allow(transport).to receive(:notify).and_raise(Manceps::TimeoutError, "timed out")

      expect(client.ping).to be false
    end
  end

  describe "session expiry retry" do
    before do
      stub_initialized_notification
    end

    it "retries request once on SessionExpiredError then succeeds" do
      # First connect succeeds
      stub_initialize

      client = described_class.new(url, auth: auth)
      client.connect

      call_count = 0
      stub_request(:post, url)
        .with(body: hash_including("method" => "tools/list"))
        .to_return do |_request|
          call_count += 1
          if call_count == 1
            { status: 404, body: "Not Found" }
          else
            {
              status: 200,
              headers: { "Content-Type" => "application/json" },
              body: JSON.generate({
                jsonrpc: "2.0", id: 4,
                result: { tools: [{ name: "retry_tool", description: "Works", inputSchema: { type: "object" } }] }
              })
            }
          end
        end

      tools = client.tools

      expect(tools.length).to eq(1)
      expect(tools.first.name).to eq("retry_tool")
    end

    it "does NOT retry on second SessionExpiredError (prevents infinite loop)" do
      stub_initialize

      client = described_class.new(url, auth: auth)
      client.connect

      # All tools/list requests return 404
      stub_request(:post, url)
        .with(body: hash_including("method" => "tools/list"))
        .to_return(status: 404, body: "Not Found")

      expect { client.tools }.to raise_error(Manceps::SessionExpiredError)
    end
  end

  describe "connect with retry" do
    it "retries on ConnectionError up to max_retries" do
      client = described_class.new(url, auth: auth, max_retries: 3)
      transport = client.instance_variable_get(:@transport)

      attempt = 0
      allow(transport).to receive(:request) do |body|
        attempt += 1
        if attempt <= 2
          raise Manceps::ConnectionError, "Connection refused"
        else
          JSON.parse(init_response_body)
        end
      end
      allow(transport).to receive(:notify)
      allow(client).to receive(:sleep)

      client.connect

      expect(attempt).to eq(3)
    end

    it "raises after max_retries exceeded" do
      client = described_class.new(url, auth: auth, max_retries: 2)
      transport = client.instance_variable_get(:@transport)

      allow(transport).to receive(:request).and_raise(Manceps::ConnectionError, "Connection refused")
      allow(client).to receive(:sleep)

      expect { client.connect }.to raise_error(Manceps::ConnectionError)
    end
  end

  describe "#batch" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "yields a Batch, executes it, and returns the Batch" do
      stub_request(:post, url)
        .with { |req| JSON.parse(req.body).is_a?(Array) }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: 2, result: { content: [{ type: "text", text: "sunny" }] } }
          ])
        )

      client = described_class.new(url, auth: auth)
      client.connect

      result = client.batch do |b|
        b.call_tool("get_weather", location: "NYC")
      end

      expect(result).to be_a(Manceps::Batch)
      expect(result.results.length).to eq(1)
    end

    it "makes batch results accessible after the block returns" do
      client = described_class.new(url, auth: auth)
      client.connect

      # We need to capture the IDs inside the block, then check results outside
      weather_id = nil

      stub_request(:post, url)
        .with { |req| JSON.parse(req.body).is_a?(Array) }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: 2, result: { content: [{ type: "text", text: "rainy" }] } }
          ])
        )

      batch = client.batch do |b|
        weather_id = b.call_tool("get_weather", location: "London")
      end

      expect(batch[weather_id]).to be_a(Manceps::ToolResult)
      expect(batch[weather_id].text).to eq("rainy")
    end
  end

  describe "transport selection" do
    it "uses StreamableHTTP for http:// URLs" do
      client = described_class.new("http://localhost:3000/mcp")
      transport = client.instance_variable_get(:@transport)

      expect(transport).to be_a(Manceps::Transport::StreamableHTTP)
    end

    it "uses StreamableHTTP for https:// URLs" do
      client = described_class.new("https://example.com/mcp", auth: auth)
      transport = client.instance_variable_get(:@transport)

      expect(transport).to be_a(Manceps::Transport::StreamableHTTP)
    end

    it "uses Stdio for non-URL strings" do
      client = described_class.new("npx", args: ["-y", "@modelcontextprotocol/server-everything"])
      transport = client.instance_variable_get(:@transport)

      expect(transport).to be_a(Manceps::Transport::Stdio)
    end

    it "uses Stdio when args: keyword is provided even with URL-like string" do
      client = described_class.new("https-server", args: ["--port", "3000"])
      transport = client.instance_variable_get(:@transport)

      expect(transport).to be_a(Manceps::Transport::Stdio)
    end

    it "passes env to Stdio transport" do
      client = described_class.new("my-server", env: { "API_KEY" => "secret" })
      transport = client.instance_variable_get(:@transport)

      expect(transport).to be_a(Manceps::Transport::Stdio)
    end
  end

  describe "pagination" do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it "follows nextCursor until nil" do
      # First page: returns one tool with a cursor
      stub_request(:post, url)
        .with(body: hash_including("method" => "tools/list", "params" => {}))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 2,
            result: {
              tools: [{ name: "tool_a", description: "First", inputSchema: { type: "object" } }],
              nextCursor: "page2"
            }
          })
        )

      # Second page: returns another tool with no cursor
      stub_request(:post, url)
        .with(body: hash_including("method" => "tools/list", "params" => { "cursor" => "page2" }))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 3,
            result: {
              tools: [{ name: "tool_b", description: "Second", inputSchema: { type: "object" } }]
            }
          })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      tools = client.tools

      expect(tools.length).to eq(2)
      expect(tools.map(&:name)).to eq(%w[tool_a tool_b])
    end
  end
end
