# Manceps

A Ruby client for the [Model Context Protocol](https://modelcontextprotocol.io) (MCP).

From Latin *manceps* -- one who takes in hand (contractor, acquirer). From *manus* (hand) + *capere* (to take).

## Installation

```ruby
# Gemfile
gem "manceps"
```

Or install directly:

```
gem install manceps
```

Requires Ruby >= 3.2.0. Single runtime dependency: [httpx](https://honeyryderchuck.gitlab.io/httpx/) for persistent HTTP connections (MCP servers bind sessions to TCP connections).

## Quick Start

```ruby
require "manceps"

Manceps::Client.open("https://mcp.example.com/mcp", auth: Manceps::Auth::Bearer.new(ENV["MCP_TOKEN"])) do |client|
  # Discover available tools
  tools = client.tools
  tools.each { |t| puts "#{t.name}: #{t.description}" }

  # Call a tool
  result = client.call_tool("search_documents", query: "quarterly report")
  puts result.text
end
```

The block form connects, yields the client, and disconnects on exit -- even if an exception is raised.

## Authentication

### Bearer Token

```ruby
auth = Manceps::Auth::Bearer.new("your-token")
client = Manceps::Client.new("https://mcp.example.com/mcp", auth: auth)
```

### API Key Header

For servers that expect a key in a custom header:

```ruby
auth = Manceps::Auth::ApiKeyHeader.new("x-api-key", "your-key")
client = Manceps::Client.new("https://mcp.example.com/mcp", auth: auth)
```

### No Auth

The default. Useful for local servers:

```ruby
client = Manceps::Client.new("http://localhost:3000/mcp")
```

## Configuration

```ruby
Manceps.configure do |c|
  c.client_name      = "MyApp"           # default: "Manceps"
  c.client_version   = "1.0.0"           # default: Manceps::VERSION
  c.protocol_version = "2025-03-26"      # default: "2025-03-26"
  c.request_timeout  = 60                # default: 30 (seconds)
  c.connect_timeout  = 15                # default: 10 (seconds)
end
```

## API Reference

### Client

```ruby
client = Manceps::Client.new(url, auth: auth, timeout: 30)
client.connect           # -> self
client.connected?        # -> true/false
client.tools             # -> Array<Tool> (paginated automatically)
client.call_tool(name, **arguments)  # -> ToolResult
client.disconnect
client.session           # -> Session (id, capabilities, server_info, protocol_version)

# Block form (preferred)
Manceps::Client.open(url, auth: auth) { |c| c.tools }
```

### Tool

```ruby
tool.name           # -> String
tool.description    # -> String
tool.input_schema   # -> Hash (JSON Schema)
tool.annotations    # -> Hash or nil
tool.to_h           # -> Hash
```

### ToolResult

```ruby
result.content      # -> Array<Content>
result.error?       # -> true/false
result.text         # -> String (joined text of all text content)
```

### Content

```ruby
content.type        # -> "text" | "image" | "resource"
content.text        # -> String (for text content)
content.data        # -> String (base64, for image/audio)
content.mime_type   # -> String
content.uri         # -> String (for resource content)
content.text?       # -> true/false
content.image?      # -> true/false
content.resource?   # -> true/false
```

## Error Handling

All errors inherit from `Manceps::Error`:

```
Manceps::Error
  Manceps::ConnectionError         # transport-level failures
  Manceps::TimeoutError            # request or connect timeout
  Manceps::ProtocolError           # JSON-RPC error from server (has #code, #data)
  Manceps::AuthenticationError     # 401/403 from server
  Manceps::SessionExpiredError     # server invalidated the session
  Manceps::ToolError               # tool invocation failed (has #result)
```

```ruby
begin
  result = client.call_tool("risky_operation", id: 42)
rescue Manceps::SessionExpiredError
  client.connect  # re-establish session
  retry
rescue Manceps::ToolError => e
  puts "Tool failed: #{e.message}"
  puts "Result: #{e.result.text}" if e.result
rescue Manceps::ProtocolError => e
  puts "RPC error #{e.code}: #{e.message}"
end
```

## Why Manceps?

**Persistent connections.** MCP's Streamable HTTP transport binds sessions to TCP connections. Manceps uses httpx under the hood to keep connections alive across requests, which most HTTP libraries don't do reliably.

**Auth-first.** Authentication is a first-class concern, not an afterthought. Plug in Bearer, API key, or (soon) OAuth strategies at construction time.

**No LLM coupling.** Manceps is a protocol client, not an AI framework. Use it with any LLM, any orchestrator, or no LLM at all.

**Extracted from production.** Built for the [Agora](https://github.com/zarpay/agentus) agent orchestration platform, where MCP connections run continuously under real load.

## Roadmap

- **v0.2** -- OAuth 2.1 authorization flow
- **v0.3** -- stdio transport, resources/list + resources/read
- **v0.4** -- prompts, streaming tool results
- **v1.0** -- stable API

## License

MIT. See [LICENSE](LICENSE) for details.

---

Author: [Obie Fernandez](https://github.com/obie)
