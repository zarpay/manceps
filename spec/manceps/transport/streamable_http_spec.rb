require "spec_helper"

RSpec.describe Manceps::Transport::StreamableHTTP do
  let(:url) { "https://example.com/mcp" }
  let(:auth) { Manceps::Auth::None.new }
  let(:transport) { described_class.new(url, auth: auth) }

  describe "#request" do
    it "sends POST with correct content-type and accept headers" do
      stub = stub_request(:post, url)
        .with(headers: {
          "Content-Type" => "application/json",
          "Accept" => "application/json, text/event-stream"
        })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
        )

      transport.request({ jsonrpc: "2.0", id: 1, method: "initialize" })

      expect(stub).to have_been_requested
    end

    it "parses JSON responses" do
      stub_request(:post, url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          jsonrpc: "2.0", id: 1,
          result: { protocolVersion: "2025-03-26", capabilities: { tools: {} } }
        })
      )

      result = transport.request({ jsonrpc: "2.0", id: 1, method: "initialize" })

      expect(result).to be_a(Hash)
      expect(result["jsonrpc"]).to eq("2.0")
      expect(result["result"]["protocolVersion"]).to eq("2025-03-26")
    end

    it "parses SSE (text/event-stream) responses" do
      sse_body = "data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tools\":[]}}\n\n"

      stub_request(:post, url).to_return(
        status: 200,
        headers: { "Content-Type" => "text/event-stream" },
        body: sse_body
      )

      result = transport.request({ jsonrpc: "2.0", id: 1, method: "tools/list" })

      expect(result).to be_a(Hash)
      expect(result[:jsonrpc]).to eq("2.0")
      expect(result[:result][:tools]).to eq([])
    end

    it "captures Mcp-Session-Id from response and sends it on subsequent requests" do
      stub_request(:post, url)
        .with { |req| req.headers["Mcp-Session-Id"].nil? }
        .to_return(
          status: 200,
          headers: {
            "Content-Type" => "application/json",
            "Mcp-Session-Id" => "session-abc-123"
          },
          body: JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
        )

      transport.request({ jsonrpc: "2.0", id: 1, method: "initialize" })

      second_stub = stub_request(:post, url)
        .with(headers: { "Mcp-Session-Id" => "session-abc-123" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 2, result: { tools: [] } })
        )

      transport.request({ jsonrpc: "2.0", id: 2, method: "tools/list" })

      expect(second_stub).to have_been_requested
    end

    it "raises AuthenticationError on 401" do
      stub_request(:post, url).to_return(status: 401, body: "Unauthorized")

      expect {
        transport.request({ jsonrpc: "2.0", id: 1, method: "initialize" })
      }.to raise_error(Manceps::AuthenticationError, /401/)
    end

    it "raises SessionExpiredError on 404" do
      stub_request(:post, url).to_return(status: 404, body: "Not Found")

      expect {
        transport.request({ jsonrpc: "2.0", id: 1, method: "tools/list" })
      }.to raise_error(Manceps::SessionExpiredError, /Session expired/)
    end

    it "raises ConnectionError on other 4xx/5xx statuses" do
      stub_request(:post, url).to_return(status: 500, body: "Internal Server Error")

      expect {
        transport.request({ jsonrpc: "2.0", id: 1, method: "tools/list" })
      }.to raise_error(Manceps::ConnectionError, /500/)
    end
  end

  describe "#notify" do
    it "sends POST and accepts 202 without error" do
      stub = stub_request(:post, url).to_return(status: 202)

      expect {
        transport.notify({ jsonrpc: "2.0", method: "notifications/initialized" })
      }.not_to raise_error

      expect(stub).to have_been_requested
    end

    it "raises on non-202 error statuses" do
      stub_request(:post, url).to_return(status: 401, body: "Unauthorized")

      expect {
        transport.notify({ jsonrpc: "2.0", method: "notifications/initialized" })
      }.to raise_error(Manceps::AuthenticationError)
    end
  end

  describe "auth header application" do
    it "applies Bearer auth headers" do
      authed_transport = described_class.new(url, auth: Manceps::Auth::Bearer.new("my-token"))

      stub = stub_request(:post, url)
        .with(headers: { "Authorization" => "Bearer my-token" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
        )

      authed_transport.request({ jsonrpc: "2.0", id: 1, method: "initialize" })

      expect(stub).to have_been_requested
    end

    it "applies ApiKeyHeader auth" do
      authed_transport = described_class.new(url, auth: Manceps::Auth::ApiKeyHeader.new("X-Api-Key", "secret-key"))

      stub = stub_request(:post, url)
        .with(headers: { "X-Api-Key" => "secret-key" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
        )

      authed_transport.request({ jsonrpc: "2.0", id: 1, method: "initialize" })

      expect(stub).to have_been_requested
    end
  end

  describe "#request_streaming" do
    it "yields intermediate SSE events and returns the final result" do
      sse_body = <<~SSE
        event: progress
        data: {"type":"progress","progress":50}

        event: message
        data: {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"done"}]}}
      SSE

      stub_request(:post, url)
        .with(body: hash_including("method" => "tools/call"))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: sse_body
        )

      yielded_events = []
      result = transport.request_streaming(
        { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "slow_tool" } }
      ) { |event| yielded_events << event }

      expect(yielded_events.length).to eq(1)
      expect(yielded_events[0]["type"]).to eq("progress")
      expect(yielded_events[0]["progress"]).to eq(50)

      expect(result).to be_a(Hash)
      expect(result["result"]["content"][0]["text"]).to eq("done")
    end

    it "returns parsed JSON when server responds with application/json" do
      stub_request(:post, url)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({
            jsonrpc: "2.0", id: 3,
            result: { content: [{ type: "text", text: "immediate" }] }
          })
        )

      yielded_events = []
      result = transport.request_streaming(
        { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "fast_tool" } }
      ) { |event| yielded_events << event }

      expect(yielded_events).to be_empty
      expect(result["result"]["content"][0]["text"]).to eq("immediate")
    end
  end

  describe "#listen" do
    it "sends GET and yields parsed notifications" do
      sse_body = <<~SSE
        event: message
        data: {"jsonrpc":"2.0","method":"notifications/tools/list_changed","params":{}}

        event: message
        data: {"jsonrpc":"2.0","method":"notifications/resources/updated","params":{"uri":"file:///config.json"}}
      SSE

      stub_request(:get, url)
        .with(headers: { "Accept" => "text/event-stream" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: sse_body
        )

      received = []
      transport.listen { |n| received << n }

      expect(received.length).to eq(2)
      expect(received[0]["method"]).to eq("notifications/tools/list_changed")
      expect(received[1]["method"]).to eq("notifications/resources/updated")
      expect(received[1]["params"]["uri"]).to eq("file:///config.json")
    end

    it "does not yield non-notification messages (responses with id)" do
      sse_body = <<~SSE
        event: message
        data: {"jsonrpc":"2.0","id":1,"result":{"tools":[]}}

        event: message
        data: {"jsonrpc":"2.0","method":"notifications/tools/list_changed","params":{}}
      SSE

      stub_request(:get, url)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: sse_body
        )

      received = []
      transport.listen { |n| received << n }

      expect(received.length).to eq(1)
      expect(received[0]["method"]).to eq("notifications/tools/list_changed")
    end

    it "does nothing when response is not event-stream" do
      stub_request(:get, url)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
        )

      received = []
      transport.listen { |n| received << n }

      expect(received).to be_empty
    end

    it "raises on error responses" do
      stub_request(:get, url).to_return(status: 401, body: "Unauthorized")

      expect {
        transport.listen { }
      }.to raise_error(Manceps::AuthenticationError)
    end

    it "includes session id header when session is established" do
      # First establish a session
      stub_request(:post, url)
        .to_return(
          status: 200,
          headers: {
            "Content-Type" => "application/json",
            "Mcp-Session-Id" => "sess-abc"
          },
          body: JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
        )

      transport.request({ jsonrpc: "2.0", id: 1, method: "initialize" })

      get_stub = stub_request(:get, url)
        .with(headers: { "Mcp-Session-Id" => "sess-abc" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: ""
        )

      transport.listen { }

      expect(get_stub).to have_been_requested
    end
  end

  describe "Last-Event-ID tracking" do
    it "tracks Last-Event-ID from SSE responses and sends it on subsequent requests" do
      sse_body = "id: evt-42\ndata: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tools\":[]}}\n\n"

      stub_request(:post, url)
        .with { |req| req.headers["Last-Event-Id"].nil? }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: sse_body
        )

      transport.request({ jsonrpc: "2.0", id: 1, method: "tools/list" })

      second_stub = stub_request(:post, url)
        .with(headers: { "Last-Event-Id" => "evt-42" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 2, result: { tools: [] } })
        )

      transport.request({ jsonrpc: "2.0", id: 2, method: "tools/list" })

      expect(second_stub).to have_been_requested
    end

    it "tracks the last event ID when multiple events have IDs" do
      sse_body = <<~SSE
        id: evt-1
        data: {"type":"progress","progress":50}

        id: evt-2
        event: message
        data: {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"done"}]}}
      SSE

      stub_request(:post, url)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: sse_body
        )

      transport.request_streaming(
        { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "tool" } }
      ) { |_| }

      second_stub = stub_request(:post, url)
        .with(headers: { "Last-Event-Id" => "evt-2" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 4, result: {} })
        )

      transport.request({ jsonrpc: "2.0", id: 4, method: "tools/list" })

      expect(second_stub).to have_been_requested
    end

    it "does not send Last-Event-ID when no SSE events had IDs" do
      stub_request(:post, url).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
      )

      transport.request({ jsonrpc: "2.0", id: 1, method: "initialize" })
      transport.request({ jsonrpc: "2.0", id: 2, method: "tools/list" })

      # Verify no request was made with Last-Event-Id header
      expect(WebMock).not_to have_requested(:post, url)
        .with { |req| req.headers.key?("Last-Event-Id") }
    end
  end

  describe "MCP-Protocol-Version header" do
    it "does NOT send MCP-Protocol-Version header before protocol_version is set" do
      stub = stub_request(:post, url)
        .with { |req| !req.headers.key?("Mcp-Protocol-Version") }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
        )

      transport.request({ jsonrpc: "2.0", id: 1, method: "initialize" })

      expect(stub).to have_been_requested
    end

    it "sends MCP-Protocol-Version header after protocol_version is set" do
      # First request without the header
      stub_request(:post, url)
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 1, result: {} })
        )

      transport.request({ jsonrpc: "2.0", id: 1, method: "initialize" })

      transport.protocol_version = "2025-11-25"

      second_stub = stub_request(:post, url)
        .with(headers: { "Mcp-Protocol-Version" => "2025-11-25" })
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate({ jsonrpc: "2.0", id: 2, result: { tools: [] } })
        )

      transport.request({ jsonrpc: "2.0", id: 2, method: "tools/list" })

      expect(second_stub).to have_been_requested
    end
  end

  describe "#terminate_session" do
    it "sends DELETE request with session id header" do
      auth_obj = Manceps::Auth::Bearer.new("tok")
      t = described_class.new(url, auth: auth_obj)

      stub = stub_request(:delete, url)
        .with(headers: {
          "Mcp-Session-Id" => "sess-42",
          "Authorization" => "Bearer tok"
        })
        .to_return(status: 200)

      t.terminate_session("sess-42")

      expect(stub).to have_been_requested
    end

    it "does not raise on 405 (method not allowed)" do
      stub_request(:delete, url).to_return(status: 405)

      expect {
        transport.terminate_session("sess-99")
      }.not_to raise_error
    end
  end
end
