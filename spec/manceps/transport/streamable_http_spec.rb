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
