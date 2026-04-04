require "spec_helper"

RSpec.describe Manceps::Batch do
  let(:url) { "https://example.com/mcp" }
  let(:auth) { Manceps::Auth::Bearer.new("test-token") }
  let(:client) { Manceps::Client.new(url, auth: auth) }

  let(:init_response_body) do
    JSON.generate({
      jsonrpc: "2.0",
      id: 1,
      result: {
        protocolVersion: "2025-11-25",
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

  before do
    stub_initialize
    stub_initialized_notification
    client.connect
  end

  describe "#call_tool" do
    it "queues a request and returns a request ID" do
      batch = described_class.new(client)
      id = batch.call_tool("get_weather", location: "NYC")

      expect(id).to be_a(Integer)
      expect(batch.requests.length).to eq(1)
      expect(batch.requests.first[:type]).to eq(:tool_call)
      expect(batch.requests.first[:body][:method]).to eq("tools/call")
    end
  end

  describe "#read_resource" do
    it "queues a request and returns a request ID" do
      batch = described_class.new(client)
      id = batch.read_resource("file:///README.md")

      expect(id).to be_a(Integer)
      expect(batch.requests.length).to eq(1)
      expect(batch.requests.first[:type]).to eq(:resource_read)
      expect(batch.requests.first[:body][:method]).to eq("resources/read")
    end
  end

  describe "#get_prompt" do
    it "queues a request and returns a request ID" do
      batch = described_class.new(client)
      id = batch.get_prompt("code_review", code: "def hello; end")

      expect(id).to be_a(Integer)
      expect(batch.requests.length).to eq(1)
      expect(batch.requests.first[:type]).to eq(:prompt_get)
      expect(batch.requests.first[:body][:method]).to eq("prompts/get")
    end
  end

  describe "queuing multiple requests" do
    it "assigns unique IDs to each request" do
      batch = described_class.new(client)
      id1 = batch.call_tool("tool_a")
      id2 = batch.read_resource("file:///a.txt")
      id3 = batch.get_prompt("prompt_a")

      expect([id1, id2, id3].uniq.length).to eq(3)
      expect(batch.requests.length).to eq(3)
    end
  end

  describe "#execute" do
    it "emits a deprecation warning" do
      batch = described_class.new(client)
      batch.call_tool("get_weather", location: "NYC")

      stub_request(:post, url)
        .with { |req| JSON.parse(req.body).is_a?(Array) }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: 2, result: { content: [{ type: "text", text: "sunny" }] } }
          ])
        )

      expect { batch.execute }.to output(
        /DEPRECATION.*JSON-RPC batching was removed from MCP spec/
      ).to_stderr
    end

    it "sends a JSON array as the batch body" do
      batch_stub = stub_request(:post, url)
        .with { |req| JSON.parse(req.body).is_a?(Array) }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: 2, result: { content: [{ type: "text", text: "sunny" }] } }
          ])
        )

      batch = described_class.new(client)
      batch.call_tool("get_weather", location: "NYC")
      batch.execute

      expect(batch_stub).to have_been_requested
    end

    it "correlates responses by ID even when out of order" do
      batch = described_class.new(client)
      weather_id = batch.call_tool("get_weather", location: "NYC")
      readme_id = batch.read_resource("file:///README.md")

      # Respond in reverse order
      stub_request(:post, url)
        .with { |req| JSON.parse(req.body).is_a?(Array) }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: readme_id, result: { contents: [{ type: "text", text: "# Hello" }] } },
            { jsonrpc: "2.0", id: weather_id, result: { content: [{ type: "text", text: "sunny" }] } }
          ])
        )

      batch.execute

      expect(batch[weather_id]).to be_a(Manceps::ToolResult)
      expect(batch[weather_id].text).to eq("sunny")
      expect(batch[readme_id]).to be_a(Manceps::ResourceContents)
      expect(batch[readme_id].text).to eq("# Hello")
    end

    it "wraps tool call results in ToolResult" do
      batch = described_class.new(client)
      id = batch.call_tool("get_weather", location: "NYC")

      stub_request(:post, url)
        .with { |req| JSON.parse(req.body).is_a?(Array) }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: id, result: { content: [{ type: "text", text: "72F" }], isError: false } }
          ])
        )

      batch.execute

      expect(batch[id]).to be_a(Manceps::ToolResult)
      expect(batch[id].text).to eq("72F")
      expect(batch[id].error?).to be false
    end

    it "wraps resource read results in ResourceContents" do
      batch = described_class.new(client)
      id = batch.read_resource("file:///readme.md")

      stub_request(:post, url)
        .with { |req| JSON.parse(req.body).is_a?(Array) }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: id, result: { contents: [{ type: "text", text: "# Project" }] } }
          ])
        )

      batch.execute

      expect(batch[id]).to be_a(Manceps::ResourceContents)
      expect(batch[id].text).to eq("# Project")
    end

    it "wraps prompt get results in PromptResult" do
      batch = described_class.new(client)
      id = batch.get_prompt("code_review", code: "def hello; end")

      stub_request(:post, url)
        .with { |req| JSON.parse(req.body).is_a?(Array) }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: id, result: {
              description: "Review code",
              messages: [{ role: "user", content: { type: "text", text: "Review: def hello; end" } }]
            } }
          ])
        )

      batch.execute

      expect(batch[id]).to be_a(Manceps::PromptResult)
      expect(batch[id].description).to eq("Review code")
      expect(batch[id].messages.first.text).to eq("Review: def hello; end")
    end

    it "stores ProtocolError for failed requests" do
      batch = described_class.new(client)
      ok_id = batch.call_tool("get_weather", location: "NYC")
      err_id = batch.call_tool("broken_tool")

      stub_request(:post, url)
        .with { |req| JSON.parse(req.body).is_a?(Array) }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: ok_id, result: { content: [{ type: "text", text: "ok" }] } },
            { jsonrpc: "2.0", id: err_id, error: { code: -32601, message: "Method not found", data: { detail: "no such tool" } } }
          ])
        )

      batch.execute

      expect(batch[ok_id]).to be_a(Manceps::ToolResult)
      expect(batch[ok_id].text).to eq("ok")

      expect(batch[err_id]).to be_a(Manceps::ProtocolError)
      expect(batch[err_id].message).to eq("Method not found")
      expect(batch[err_id].code).to eq(-32601)
      expect(batch[err_id].data).to eq({ "detail" => "no such tool" })
    end

    it "returns empty hash for empty batch" do
      batch = described_class.new(client)
      result = batch.execute

      expect(result).to eq({})
      expect(batch.results).to eq({})
    end

    it "handles mixed request types in a single batch" do
      batch = described_class.new(client)
      tool_id = batch.call_tool("echo", message: "hi")
      resource_id = batch.read_resource("file:///a.txt")
      prompt_id = batch.get_prompt("summarize", text: "long text")

      stub_request(:post, url)
        .with { |req|
          body = JSON.parse(req.body)
          body.is_a?(Array) && body.length == 3
        }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: prompt_id, result: { description: "Summary", messages: [] } },
            { jsonrpc: "2.0", id: tool_id, result: { content: [{ type: "text", text: "hi" }] } },
            { jsonrpc: "2.0", id: resource_id, result: { contents: [{ type: "text", text: "file content" }] } }
          ])
        )

      batch.execute

      expect(batch[tool_id]).to be_a(Manceps::ToolResult)
      expect(batch[resource_id]).to be_a(Manceps::ResourceContents)
      expect(batch[prompt_id]).to be_a(Manceps::PromptResult)
    end
  end

  describe "#[]" do
    it "returns nil for unknown IDs" do
      batch = described_class.new(client)
      expect(batch[999]).to be_nil
    end

    it "retrieves results by ID after execute" do
      batch = described_class.new(client)
      id = batch.call_tool("echo", message: "hi")

      stub_request(:post, url)
        .with { |req| JSON.parse(req.body).is_a?(Array) }
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: JSON.generate([
            { jsonrpc: "2.0", id: id, result: { content: [{ type: "text", text: "hi" }] } }
          ])
        )

      batch.execute

      expect(batch[id]).to be_a(Manceps::ToolResult)
      expect(batch[id].text).to eq("hi")
    end
  end
end
