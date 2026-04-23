# Changelog

All notable changes to Manceps are documented here.

## [1.0.1] - 2026-04-23

### Fixed

- SSE responses now return string keys consistently with the rest of the client. `SSEParser.extract_json` previously parsed JSON with `symbolize_names: true`, which caused `Client#tools`, `#prompts`, and `#resources` to silently return `[]` and `Client#call_tool`, `#get_prompt`, and `#read_resource` to raise `NoMethodError` whenever the server replied with `Content-Type: text/event-stream`. Thanks to [@keithmgould](https://github.com/keithmgould) for the fix (#1).

## [1.0.0] - 2026-04-06

First public release. A production-grade Ruby client for the Model Context Protocol (MCP).

### Features

- **Streamable HTTP transport** with persistent connections via httpx
- **stdio transport** for local MCP servers (subprocess communication over stdin/stdout)
- **Auto-detect transport** from URL vs command
- **Authentication**: Bearer token, API key header, OAuth token support with auto-refresh
- **Tools**: list, call, streaming calls, structured output support
- **Resources**: list, read, templates
- **Prompts**: list, get with arguments
- **Notifications**: register handlers, subscribe to resource updates, cancel requests
- **Elicitation**: handle server requests for additional user input
- **Tasks** (experimental): list, get, cancel, await with polling
- **Resilience**: automatic retry with exponential backoff, session recovery on 404
- **Pagination**: automatic cursor-based pagination for list operations
- **Protocol negotiation**: targets MCP 2025-11-25, falls back to 2025-06-18 and 2025-03-26
- **Configuration**: client name, version, timeouts, supported protocol versions
- **Full error hierarchy**: ConnectionError, TimeoutError, ProtocolError, AuthenticationError, SessionExpiredError, ToolError

### Requirements

- Ruby >= 3.4.0
- httpx >= 1.0
