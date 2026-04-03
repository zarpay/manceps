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
