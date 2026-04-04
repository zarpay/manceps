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

Requires Ruby >= 3.2.0.

## Quick Start

```ruby
require "manceps"

# HTTP server with bearer auth
Manceps::Client.open("https://mcp.example.com/mcp", auth: Manceps::Auth::Bearer.new(ENV["MCP_TOKEN"])) do |client|
  client.tools.each { |t| puts "#{t.name}: #{t.description}" }

  result = client.call_tool("search_documents", query: "quarterly report")
  puts result.text
end

# stdio server (local process)
Manceps::Client.open("npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]) do |client|
  contents = client.read_resource("file:///tmp/hello.txt")
  puts contents.text
end
```

The block form connects, yields the client, and disconnects on exit -- even if an exception is raised.

## Transports

### Streamable HTTP

The primary MCP transport. Uses [httpx](https://honeyryderchuck.gitlab.io/httpx/) for persistent connections -- MCP servers bind sessions to TCP connections, so connection reuse is required.

```ruby
client = Manceps::Client.new("https://mcp.example.com/mcp", auth: auth)
```

### stdio

Spawns a local subprocess and communicates via newline-delimited JSON over stdin/stdout.

```ruby
client = Manceps::Client.new("npx", args: ["-y", "@modelcontextprotocol/server-memory"])

# With environment variables
client = Manceps::Client.new("mm-mcp", env: { "MM_TOKEN" => "...", "MM_URL" => "..." })
```

The transport auto-detects: HTTP(S) URLs use Streamable HTTP, everything else uses stdio.

## Authentication

### Bearer Token

```ruby
auth = Manceps::Auth::Bearer.new("your-token")
```

### API Key Header

```ruby
auth = Manceps::Auth::ApiKeyHeader.new("x-api-key", "your-key")
```

### OAuth 2.1

Full OAuth flow with RFC 8414 discovery, RFC 7591 dynamic registration, PKCE, and automatic token refresh.

```ruby
# If you already have tokens
auth = Manceps::Auth::OAuth.new(
  access_token: "...",
  refresh_token: "...",
  token_url: "https://auth.example.com/token",
  client_id: "...",
  expires_at: Time.now + 3600,
  on_token_refresh: ->(tokens) { save_tokens(tokens) }
)

# Full discovery + authorization flow
discovery = Manceps::Auth::OAuth.discover("https://mcp.example.com", redirect_uri: "http://localhost:3000/callback")
pkce = Manceps::Auth::OAuth.generate_pkce

url = Manceps::Auth::OAuth.authorize_url(
  authorization_url: discovery.authorization_url,
  client_id: discovery.client_id,
  redirect_uri: "http://localhost:3000/callback",
  state: SecureRandom.hex(16),
  scopes: discovery.scopes,
  code_challenge: pkce[:challenge]
)
# Redirect user to `url`, then exchange the code:

tokens = Manceps::Auth::OAuth.exchange_code(
  token_url: discovery.token_url,
  client_id: discovery.client_id,
  client_secret: discovery.client_secret,
  code: params[:code],
  redirect_uri: "http://localhost:3000/callback",
  code_verifier: pkce[:verifier]
)
```

Token refresh happens automatically when a token is within 5 minutes of expiry. The `on_token_refresh` callback fires after each refresh so you can persist the new tokens.

### No Auth

The default. Useful for local servers:

```ruby
client = Manceps::Client.new("http://localhost:3000/mcp")
```

## Tools

```ruby
# List available tools
tools = client.tools
tools.each do |tool|
  puts "#{tool.title || tool.name}: #{tool.description}"
  puts "  Input:  #{tool.input_schema}"
  puts "  Output: #{tool.output_schema}" if tool.output_schema  # structured output (2025-06-18+)
end

# Call a tool
result = client.call_tool("get_weather", location: "New York")
result.text                # joined text content
result.content             # Array<Content>
result.error?              # true if server flagged an error
result.structured_content  # parsed structured output (when tool declares outputSchema)
result.structured?         # true if structured content present

# Stream a long-running tool call
client.call_tool_streaming("analyze_data", dataset: "large.csv") do |event|
  puts "Progress: #{event}"
end
```

## Resources

```ruby
# List resources
resources = client.resources
resources.each { |r| puts "#{r.uri}: #{r.title || r.name}" }

# List resource templates
templates = client.resource_templates
templates.each { |t| puts "#{t.uri_template}: #{t.title || t.name}" }

# Read a resource
contents = client.read_resource("file:///project/src/main.rs")
puts contents.text
```

## Prompts

```ruby
# List prompts
prompts = client.prompts
prompts.each do |p|
  puts "#{p.name}: #{p.description}"
  p.arguments.each { |a| puts "  #{a.name} (required: #{a.required?})" }
end

# Get a prompt
result = client.get_prompt("code_review", code: "def hello; end")
result.messages.each { |m| puts "#{m.role}: #{m.text}" }
```

## Configuration

```ruby
Manceps.configure do |c|
  c.client_name      = "MyApp"           # default: "Manceps"
  c.client_version   = "1.0.0"           # default: Manceps::VERSION
  c.protocol_version = "2025-11-25"      # default: "2025-11-25"
  c.request_timeout  = 60                # default: 30 (seconds)
  c.connect_timeout  = 15                # default: 10 (seconds)
  c.client_description = "My app"        # optional, sent in clientInfo
  c.supported_versions = ["2025-11-25", "2025-06-18", "2025-03-26"]  # for negotiation
end
```

## Error Handling

All errors inherit from `Manceps::Error`:

```
Manceps::Error
  Manceps::ConnectionError         # transport-level failures
  Manceps::TimeoutError            # request or connect timeout
  Manceps::ProtocolError           # JSON-RPC error (has #code, #data)
  Manceps::AuthenticationError     # 401, failed OAuth flows
  Manceps::SessionExpiredError     # server invalidated the session (404)
  Manceps::ToolError               # tool invocation failed (has #result)
```

```ruby
begin
  result = client.call_tool("risky_operation", id: 42)
rescue Manceps::SessionExpiredError
  client.connect  # re-establish session
  retry
rescue Manceps::ProtocolError => e
  puts "RPC error #{e.code}: #{e.message}"
end
```

## Why Manceps?

**Persistent connections.** MCP servers bind sessions to TCP connections. Manceps uses httpx to keep connections alive across requests, which most HTTP libraries don't do by default.

**Auth-first.** Bearer, API key, and OAuth 2.1 (with PKCE and auto-refresh) are built in, not bolted on.

**No LLM coupling.** Pure protocol client. No `to_openai_tools()` or framework integrations -- use it with anything.

**Extracted from production.** The protocol handling and OAuth flows come from [Agora](https://github.com/zarpay/agentus), where MCP connections run under real load.

**Full 2025-11-25 spec.** Protocol version negotiation, elicitation, tasks, structured tool output, `MCP-Protocol-Version` header -- not just the basics.

## Notifications

Register handlers for server-initiated messages:

```ruby
client.on("notifications/tools/list_changed") { puts "Tools changed!" }
client.on("notifications/resources/updated") { |params| puts "Updated: #{params['uri']}" }

# Subscribe to resource updates
client.subscribe_resource("file:///project/config.yml")

# Cancel a long-running request
client.cancel_request(request_id, reason: "User cancelled")

# Listen for notifications (blocking)
client.listen  # dispatches to registered handlers
```

## Elicitation

Handle server requests for additional user input during tool calls:

```ruby
client.on_elicitation do |elicitation|
  puts "Server asks: #{elicitation.message}"
  puts "Schema: #{elicitation.requested_schema}"

  # Respond with user input
  Manceps::Elicitation.accept({ "name" => "Alice", "confirm" => true })
  # Or decline/cancel:
  # Manceps::Elicitation.decline
  # Manceps::Elicitation.cancel
end
```

Elicitation capability is automatically declared during initialization when a handler is registered.

## Tasks (Experimental)

Track long-running operations:

```ruby
# List tasks
client.tasks.each { |t| puts "#{t.id}: #{t.status}" }

# Get a specific task
task = client.get_task("task-123")
task.completed?  # => false
task.running?    # => true

# Poll until done
task = client.await_task("task-123", interval: 2, timeout: 60)
puts task.result

# Cancel a task
client.cancel_task("task-123")
```

## Batch Requests (Deprecated)

> JSON-RPC batching was removed from the MCP spec in 2025-06-18. This feature emits a deprecation warning and will be removed in a future version.

```ruby
batch = client.batch do |b|
  weather_id = b.call_tool("get_weather", location: "NYC")
  readme_id = b.read_resource("file:///README.md")
end
batch[weather_id]  # => ToolResult
```

## Resilience

Automatic retry with exponential backoff on connection failures:

```ruby
# Connect retries up to max_retries (default: 3)
client = Manceps::Client.new("https://mcp.example.com/mcp", auth: auth, max_retries: 5)

# Requests auto-retry once on session expiry (re-initializes session)
client.call_tool("search", query: "test")  # retries transparently on 404

# Check connection health
client.ping  # => true/false

# Manual reconnect
client.reconnect!
```

## Protocol Version

Manceps targets MCP protocol **2025-11-25** by default. It negotiates with the server during initialization and supports fallback to `2025-06-18` and `2025-03-26`.

After initialization, the `MCP-Protocol-Version` header is included on all HTTP requests per the spec.

## License

MIT. See [LICENSE](LICENSE) for details.

---

Author: [Obie Fernandez](https://github.com/obie)
