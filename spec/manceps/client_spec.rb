# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Manceps::Client do
  let(:url) { 'https://example.com/mcp' }
  let(:auth) { Manceps::Auth::Bearer.new('test-token') }

  # Shared stubs
  let(:init_response_body) do
    JSON.generate({
                    jsonrpc: '2.0',
                    id: 1,
                    result: {
                      protocolVersion: '2025-11-25',
                      capabilities: { tools: {} },
                      serverInfo: { name: 'TestServer', version: '1.0' }
                    }
                  })
  end

  let(:init_response_headers) do
    { 'Content-Type' => 'application/json', 'Mcp-Session-Id' => 'test-session-123' }
  end

  def stub_initialize
    stub_request(:post, url)
      .with(
        body: hash_including('method' => 'initialize'),
        headers: { 'Authorization' => 'Bearer test-token' }
      )
      .to_return(
        status: 200,
        headers: init_response_headers,
        body: init_response_body
      )
  end

  def stub_initialized_notification
    stub_request(:post, url)
      .with(body: hash_including('method' => 'notifications/initialized'))
      .to_return(status: 202)
  end

  def stub_tools_list(tools: [], next_cursor: nil)
    result = { tools: tools }
    result[:nextCursor] = next_cursor if next_cursor

    stub_request(:post, url)
      .with(body: hash_including('method' => 'tools/list'))
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({ jsonrpc: '2.0', id: 2, result: result })
      )
  end

  def stub_tool_call(result_content)
    stub_request(:post, url)
      .with(body: hash_including('method' => 'tools/call'))
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({
                              jsonrpc: '2.0', id: 2,
                              result: { content: result_content, isError: false }
                            })
      )
  end

  def stub_delete_session
    stub_request(:delete, url).to_return(status: 200)
  end

  describe '#connect' do
    it 'sends initialize request followed by initialized notification' do
      init_stub = stub_initialize
      notif_stub = stub_initialized_notification

      client = described_class.new(url, auth: auth)
      client.connect

      expect(init_stub).to have_been_requested
      expect(notif_stub).to have_been_requested
    end

    it 'returns self for chaining' do
      stub_initialize
      stub_initialized_notification

      client = described_class.new(url, auth: auth)
      result = client.connect

      expect(result).to be(client)
    end

    it 'stores session info from server response' do
      stub_initialize
      stub_initialized_notification

      client = described_class.new(url, auth: auth)
      client.connect

      # The transport captures Mcp-Session-Id and sends it on subsequent
      # requests, verified by header assertions in other specs.
      expect(client.session).to be_a(Manceps::Session)
    end

    it 'sets protocol_version on the transport after initialization' do
      stub_initialize
      stub_initialized_notification

      client = described_class.new(url, auth: auth)
      client.connect

      transport = client.instance_variable_get(:@transport)
      expect(transport.instance_variable_get(:@protocol_version)).to eq('2025-11-25')
    end

    it 'raises ProtocolError when server returns an unsupported protocol version' do
      unsupported_init_body = JSON.generate({
                                              jsonrpc: '2.0',
                                              id: 1,
                                              result: {
                                                protocolVersion: '2024-01-01',
                                                capabilities: { tools: {} },
                                                serverInfo: { name: 'TestServer', version: '1.0' }
                                              }
                                            })

      stub_request(:post, url)
        .with(
          body: hash_including('method' => 'initialize'),
          headers: { 'Authorization' => 'Bearer test-token' }
        )
        .to_return(
          status: 200,
          headers: init_response_headers,
          body: unsupported_init_body
        )

      stub_delete_session

      client = described_class.new(url, auth: auth)

      expect { client.connect }.to raise_error(Manceps::ProtocolError, /unsupported protocol version.*2024-01-01/)
    end

    it 'succeeds when server returns a supported older version' do
      older_init_body = JSON.generate({
                                        jsonrpc: '2.0',
                                        id: 1,
                                        result: {
                                          protocolVersion: '2025-03-26',
                                          capabilities: { tools: {} },
                                          serverInfo: { name: 'TestServer', version: '1.0' }
                                        }
                                      })

      stub_request(:post, url)
        .with(
          body: hash_including('method' => 'initialize'),
          headers: { 'Authorization' => 'Bearer test-token' }
        )
        .to_return(
          status: 200,
          headers: init_response_headers,
          body: older_init_body
        )
      stub_initialized_notification

      client = described_class.new(url, auth: auth)
      client.connect

      expect(client.session.protocol_version).to eq('2025-03-26')
    end
  end

  describe '#tools' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'returns an array of Tool objects' do
      stub_tools_list(tools: [
                        { name: 'get_weather', description: 'Get weather', inputSchema: { type: 'object' } },
                        { name: 'search', description: 'Search the web', inputSchema: { type: 'object' } }
                      ])

      client = described_class.new(url, auth: auth)
      client.connect
      tools = client.tools

      expect(tools.length).to eq(2)
      expect(tools).to all(be_a(Manceps::Tool))
      expect(tools.first.name).to eq('get_weather')
      expect(tools.first.description).to eq('Get weather')
      expect(tools.last.name).to eq('search')
    end

    it 'returns empty array when server has no tools' do
      stub_tools_list(tools: [])

      client = described_class.new(url, auth: auth)
      client.connect

      expect(client.tools).to eq([])
    end
  end

  describe '#call_tool' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'sends tools/call and returns a ToolResult' do
      stub_tool_call([{ type: 'text', text: 'Sunny, 72F' }])

      client = described_class.new(url, auth: auth)
      client.connect
      result = client.call_tool('get_weather', location: 'NYC')

      expect(result).to be_a(Manceps::ToolResult)
      expect(result.text).to eq('Sunny, 72F')
      expect(result.error?).to be false
    end

    it 'includes tool arguments in the request' do
      call_stub = stub_request(:post, url)
                  .with(body: hash_including(
                    'method' => 'tools/call',
                    'params' => hash_including(
                      'name' => 'get_weather',
                      'arguments' => { 'location' => 'NYC' }
                    )
                  ))
                  .to_return(
                    status: 200,
                    headers: { 'Content-Type' => 'application/json' },
                    body: JSON.generate({
                                          jsonrpc: '2.0', id: 2,
                                          result: { content: [{ type: 'text', text: 'ok' }], isError: false }
                                        })
                  )

      client = described_class.new(url, auth: auth)
      client.connect
      client.call_tool('get_weather', location: 'NYC')

      expect(call_stub).to have_been_requested
    end
  end

  describe '#prompts' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'returns an array of Prompt objects' do
      stub_request(:post, url)
        .with(body: hash_including('method' => 'prompts/list'))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({
                                jsonrpc: '2.0', id: 2,
                                result: {
                                  prompts: [
                                    { name: 'code_review', description: 'Review code',
                                      arguments: [{ name: 'code', required: true }] },
                                    { name: 'summarize', description: 'Summarize text' }
                                  ]
                                }
                              })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      prompts = client.prompts

      expect(prompts.length).to eq(2)
      expect(prompts).to all(be_a(Manceps::Prompt))
      expect(prompts.first.name).to eq('code_review')
      expect(prompts.first.arguments.length).to eq(1)
      expect(prompts.last.name).to eq('summarize')
    end
  end

  describe '#get_prompt' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'sends prompts/get and returns a PromptResult' do
      stub_request(:post, url)
        .with(body: hash_including(
          'method' => 'prompts/get',
          'params' => hash_including('name' => 'code_review', 'arguments' => { 'code' => 'puts 1' })
        ))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({
                                jsonrpc: '2.0', id: 2,
                                result: {
                                  description: 'Code review prompt',
                                  messages: [
                                    { role: 'user', content: { type: 'text', text: 'Review: puts 1' } }
                                  ]
                                }
                              })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      result = client.get_prompt('code_review', code: 'puts 1')

      expect(result).to be_a(Manceps::PromptResult)
      expect(result.description).to eq('Code review prompt')
      expect(result.messages.length).to eq(1)
      expect(result.messages.first.role).to eq('user')
      expect(result.messages.first.text).to eq('Review: puts 1')
    end
  end

  describe '#call_tool_streaming' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'yields intermediate events and returns a ToolResult' do
      sse_body = <<~SSE
        event: progress
        data: {"type":"progress","progress":50}

        event: message
        data: {"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"done"}],"isError":false}}
      SSE

      stub_request(:post, url)
        .with(body: hash_including('method' => 'tools/call'))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'text/event-stream' },
          body: sse_body
        )

      client = described_class.new(url, auth: auth)
      client.connect

      yielded_events = []
      result = client.call_tool_streaming('slow_tool', input: 'data') { |e| yielded_events << e }

      expect(result).to be_a(Manceps::ToolResult)
      expect(result.text).to eq('done')
      expect(yielded_events.length).to eq(1)
      expect(yielded_events[0]['type']).to eq('progress')
    end
  end

  describe '#disconnect' do
    it 'calls close on the transport and resets the session' do
      stub_initialize
      stub_initialized_notification
      stub_delete_session

      client = described_class.new(url, auth: auth)
      client.connect
      client.disconnect

      expect(client.session.active?).to be false
    end

    it "sends terminate_session with the transport's session ID (not nil)" do
      stub_initialize
      stub_initialized_notification
      delete_stub = stub_request(:delete, url)
                    .with(headers: { 'Mcp-Session-Id' => 'test-session-123' })
                    .to_return(status: 200)

      client = described_class.new(url, auth: auth)
      client.connect
      client.disconnect

      expect(delete_stub).to have_been_requested
    end
  end

  describe '.open' do
    it 'connects, yields the client, and disconnects' do
      stub_initialize
      stub_initialized_notification
      stub_tools_list(tools: [
                        { name: 'echo', description: 'Echo input', inputSchema: { type: 'object' } }
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

    it 'disconnects even when block raises' do
      stub_initialize
      stub_initialized_notification
      stub_delete_session

      client_ref = nil

      expect do
        described_class.open(url, auth: auth) do |client|
          client_ref = client
          raise 'boom'
        end
      end.to raise_error(RuntimeError, 'boom')

      expect(client_ref.session.active?).to be false
    end
  end

  describe 'JSON-RPC error handling' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'raises ProtocolError when server returns a JSON-RPC error' do
      stub_request(:post, url)
        .with(body: hash_including('method' => 'tools/list'))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({
                                jsonrpc: '2.0', id: 2,
                                error: { code: -32_601, message: 'Method not found' }
                              })
        )

      client = described_class.new(url, auth: auth)
      client.connect

      expect { client.tools }.to raise_error(Manceps::ProtocolError) do |err|
        expect(err.message).to eq('Method not found')
        expect(err.code).to eq(-32_601)
      end
    end

    it 'raises ProtocolError when initialize itself returns an error' do
      # Override the default init stub for this test
      WebMock.reset!

      stub_request(:post, url)
        .with(body: hash_including('method' => 'initialize'))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({
                                jsonrpc: '2.0', id: 1,
                                error: { code: -32_600, message: 'Invalid protocol version' }
                              })
        )

      client = described_class.new(url, auth: auth)

      expect { client.connect }.to raise_error(Manceps::ProtocolError, 'Invalid protocol version')
    end

    it 'raises ProtocolError from symbol-keyed error response' do
      client = described_class.new(url, auth: auth)
      client.connect

      response = { error: { code: -32_601, message: 'Method not found', data: 'extra' } }

      expect { client.send(:handle_rpc_error, response) }.to raise_error(Manceps::ProtocolError) do |err|
        expect(err.message).to eq('Method not found')
        expect(err.code).to eq(-32_601)
        expect(err.data).to eq('extra')
      end
    end

    it 'raises with default message when error has no message' do
      client = described_class.new(url, auth: auth)
      client.connect

      response = { 'error' => { 'code' => -32_000 } }

      expect do
        client.send(:handle_rpc_error, response)
      end.to raise_error(Manceps::ProtocolError, 'Unknown JSON-RPC error')
    end

    it 'does not raise when response has no error key' do
      client = described_class.new(url, auth: auth)
      client.connect

      response = { 'result' => { 'tools' => [] } }

      expect { client.send(:handle_rpc_error, response) }.not_to raise_error
    end

    it 'does not raise when response is not a Hash' do
      client = described_class.new(url, auth: auth)
      client.connect

      expect { client.send(:handle_rpc_error, nil) }.not_to raise_error
      expect { client.send(:handle_rpc_error, 'string') }.not_to raise_error
    end
  end

  describe '#resources' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'returns an array of Resource objects' do
      stub_request(:post, url)
        .with(body: hash_including('method' => 'resources/list'))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({
                                jsonrpc: '2.0', id: 2,
                                result: {
                                  resources: [
                                    { uri: 'file:///readme.md', name: 'README', description: 'Project readme',
                                      mimeType: 'text/markdown' },
                                    { uri: 'file:///config.json', name: 'Config', description: 'App config' }
                                  ]
                                }
                              })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      resources = client.resources

      expect(resources.length).to eq(2)
      expect(resources).to all(be_a(Manceps::Resource))
      expect(resources.first.uri).to eq('file:///readme.md')
      expect(resources.first.name).to eq('README')
      expect(resources.first.mime_type).to eq('text/markdown')
      expect(resources.last.uri).to eq('file:///config.json')
    end

    it 'returns empty array when server has no resources' do
      stub_request(:post, url)
        .with(body: hash_including('method' => 'resources/list'))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({ jsonrpc: '2.0', id: 2, result: { resources: [] } })
        )

      client = described_class.new(url, auth: auth)
      client.connect

      expect(client.resources).to eq([])
    end
  end

  describe '#resource_templates' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'returns an array of ResourceTemplate objects' do
      stub_request(:post, url)
        .with(body: hash_including('method' => 'resources/templates/list'))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({
                                jsonrpc: '2.0', id: 2,
                                result: {
                                  resourceTemplates: [
                                    { uriTemplate: 'file:///logs/{date}.log', name: 'Daily Log', description: 'Logs by date' }
                                  ]
                                }
                              })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      templates = client.resource_templates

      expect(templates.length).to eq(1)
      expect(templates.first).to be_a(Manceps::ResourceTemplate)
      expect(templates.first.uri_template).to eq('file:///logs/{date}.log')
      expect(templates.first.name).to eq('Daily Log')
    end
  end

  describe '#read_resource' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'sends resources/read and returns ResourceContents' do
      stub_request(:post, url)
        .with(body: hash_including(
          'method' => 'resources/read',
          'params' => hash_including('uri' => 'file:///readme.md')
        ))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({
                                jsonrpc: '2.0', id: 2,
                                result: {
                                  contents: [
                                    { type: 'text', text: "# Hello\nWelcome to the project", uri: 'file:///readme.md', mimeType: 'text/markdown' }
                                  ]
                                }
                              })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      result = client.read_resource('file:///readme.md')

      expect(result).to be_a(Manceps::ResourceContents)
      expect(result.contents.length).to eq(1)
      expect(result.text).to eq("# Hello\nWelcome to the project")
    end
  end

  describe '#on' do
    it 'registers notification handlers' do
      client = described_class.new(url, auth: auth)
      received = []
      client.on('notifications/tools/list_changed') { |params| received << params }

      handlers = client.instance_variable_get(:@notification_handlers)
      expect(handlers['notifications/tools/list_changed'].length).to eq(1)
    end

    it 'allows multiple handlers for the same notification' do
      client = described_class.new(url, auth: auth)
      client.on('notifications/tools/list_changed') { nil }
      client.on('notifications/tools/list_changed') { nil }

      handlers = client.instance_variable_get(:@notification_handlers)
      expect(handlers['notifications/tools/list_changed'].length).to eq(2)
    end
  end

  describe '#subscribe_resource' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'sends resources/subscribe with the URI' do
      sub_stub = stub_request(:post, url)
                 .with(body: hash_including(
                   'method' => 'resources/subscribe',
                   'params' => hash_including('uri' => 'file:///readme.md')
                 ))
                 .to_return(
                   status: 200,
                   headers: { 'Content-Type' => 'application/json' },
                   body: JSON.generate({ jsonrpc: '2.0', id: 3, result: {} })
                 )

      client = described_class.new(url, auth: auth)
      client.connect
      client.subscribe_resource('file:///readme.md')

      expect(sub_stub).to have_been_requested
    end
  end

  describe '#unsubscribe_resource' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'sends resources/unsubscribe with the URI' do
      unsub_stub = stub_request(:post, url)
                   .with(body: hash_including(
                     'method' => 'resources/unsubscribe',
                     'params' => hash_including('uri' => 'file:///readme.md')
                   ))
                   .to_return(
                     status: 200,
                     headers: { 'Content-Type' => 'application/json' },
                     body: JSON.generate({ jsonrpc: '2.0', id: 3, result: {} })
                   )

      client = described_class.new(url, auth: auth)
      client.connect
      client.unsubscribe_resource('file:///readme.md')

      expect(unsub_stub).to have_been_requested
    end
  end

  describe '#cancel_request' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'sends notifications/cancelled with the request ID' do
      cancel_stub = stub_request(:post, url)
                    .with(body: hash_including(
                      'method' => 'notifications/cancelled',
                      'params' => hash_including('requestId' => 42)
                    ))
                    .to_return(status: 202)

      client = described_class.new(url, auth: auth)
      client.connect
      client.cancel_request(42)

      expect(cancel_stub).to have_been_requested
    end

    it 'includes reason when provided' do
      cancel_stub = stub_request(:post, url)
                    .with(body: hash_including(
                      'method' => 'notifications/cancelled',
                      'params' => hash_including('requestId' => 42, 'reason' => 'User cancelled')
                    ))
                    .to_return(status: 202)

      client = described_class.new(url, auth: auth)
      client.connect
      client.cancel_request(42, reason: 'User cancelled')

      expect(cancel_stub).to have_been_requested
    end
  end

  describe '#listen' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'dispatches notifications to registered handlers' do
      sse_body = <<~SSE
        event: message
        data: {"jsonrpc":"2.0","method":"notifications/tools/list_changed","params":{}}

        event: message
        data: {"jsonrpc":"2.0","method":"notifications/resources/updated","params":{"uri":"file:///config.json"}}
      SSE

      stub_request(:get, url)
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'text/event-stream' },
          body: sse_body
        )

      client = described_class.new(url, auth: auth)
      client.connect

      tools_changed = []
      resources_updated = []
      client.on('notifications/tools/list_changed') { |params| tools_changed << params }
      client.on('notifications/resources/updated') { |params| resources_updated << params }

      client.listen

      expect(tools_changed.length).to eq(1)
      expect(resources_updated.length).to eq(1)
      expect(resources_updated.first).to eq({ 'uri' => 'file:///config.json' })
    end
  end

  describe '#tools with force:' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'accepts force: true parameter' do
      stub_tools_list(tools: [])

      client = described_class.new(url, auth: auth)
      client.connect

      expect { client.tools(force: true) }.not_to raise_error
    end
  end

  describe '#reconnect!' do
    before do
      stub_initialized_notification
    end

    it 'closes transport, resets session, and re-initializes' do
      init_stub = stub_initialize

      client = described_class.new(url, auth: auth)
      client.connect

      # reconnect! should close, reset, and re-connect
      client.reconnect!

      # initialize should have been called twice (once for connect, once for reconnect)
      expect(init_stub).to have_been_requested.times(2)
    end

    it 'resets the session request counter' do
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

  describe '#ping' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'returns true on success' do
      stub_request(:post, url)
        .with(body: hash_including('method' => 'ping'))
        .to_return(status: 202)

      client = described_class.new(url, auth: auth)
      client.connect

      expect(client.ping).to be true
    end

    it 'returns false on ConnectionError' do
      client = described_class.new(url, auth: auth)
      client.connect

      transport = client.instance_variable_get(:@transport)
      allow(transport).to receive(:notify).and_raise(Manceps::ConnectionError, 'gone')

      expect(client.ping).to be false
    end

    it 'returns false on TimeoutError' do
      client = described_class.new(url, auth: auth)
      client.connect

      transport = client.instance_variable_get(:@transport)
      allow(transport).to receive(:notify).and_raise(Manceps::TimeoutError, 'timed out')

      expect(client.ping).to be false
    end
  end

  describe 'session expiry retry' do
    before do
      stub_initialized_notification
    end

    it 'retries request once on SessionExpiredError then succeeds' do
      # First connect succeeds
      stub_initialize

      client = described_class.new(url, auth: auth)
      client.connect

      call_count = 0
      stub_request(:post, url)
        .with(body: hash_including('method' => 'tools/list'))
        .to_return do |_request|
          call_count += 1
          if call_count == 1
            { status: 404, body: 'Not Found' }
          else
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: JSON.generate({
                                    jsonrpc: '2.0', id: 4,
                                    result: { tools: [{ name: 'retry_tool', description: 'Works', inputSchema: { type: 'object' } }] }
                                  })
            }
          end
        end

      tools = client.tools

      expect(tools.length).to eq(1)
      expect(tools.first.name).to eq('retry_tool')
    end

    it 'does NOT retry on second SessionExpiredError (prevents infinite loop)' do
      stub_initialize

      client = described_class.new(url, auth: auth)
      client.connect

      # All tools/list requests return 404
      stub_request(:post, url)
        .with(body: hash_including('method' => 'tools/list'))
        .to_return(status: 404, body: 'Not Found')

      expect { client.tools }.to raise_error(Manceps::SessionExpiredError)
    end
  end

  describe 'connect with retry' do
    it 'retries on ConnectionError up to max_retries' do
      client = described_class.new(url, auth: auth, max_retries: 3)
      transport = client.instance_variable_get(:@transport)

      attempt = 0
      allow(transport).to receive(:request) do |_body|
        attempt += 1
        raise Manceps::ConnectionError, 'Connection refused' if attempt <= 2

        JSON.parse(init_response_body)
      end
      allow(transport).to receive(:notify)
      allow(client).to receive(:sleep)

      client.connect

      expect(attempt).to eq(3)
    end

    it 'raises after max_retries exceeded' do
      client = described_class.new(url, auth: auth, max_retries: 2)
      transport = client.instance_variable_get(:@transport)

      allow(transport).to receive(:request).and_raise(Manceps::ConnectionError, 'Connection refused')
      allow(client).to receive(:sleep)

      expect { client.connect }.to raise_error(Manceps::ConnectionError)
    end

    it 'closes transport before each retry' do
      client = described_class.new(url, auth: auth, max_retries: 3)
      transport = client.instance_variable_get(:@transport)

      attempt = 0
      allow(transport).to receive(:request) do |_body|
        attempt += 1
        raise Manceps::ConnectionError, 'Connection refused' if attempt <= 2

        JSON.parse(init_response_body)
      end
      allow(transport).to receive(:notify)
      allow(transport).to receive(:close)
      allow(client).to receive(:sleep)

      client.connect

      expect(transport).to have_received(:close).exactly(2).times
    end
  end

  describe 'transport selection' do
    it 'uses StreamableHTTP for http:// URLs' do
      client = described_class.new('http://localhost:3000/mcp')
      transport = client.instance_variable_get(:@transport)

      expect(transport).to be_a(Manceps::Transport::StreamableHTTP)
    end

    it 'uses StreamableHTTP for https:// URLs' do
      client = described_class.new('https://example.com/mcp', auth: auth)
      transport = client.instance_variable_get(:@transport)

      expect(transport).to be_a(Manceps::Transport::StreamableHTTP)
    end

    it 'uses Stdio for non-URL strings' do
      client = described_class.new('npx', args: ['-y', '@modelcontextprotocol/server-everything'])
      transport = client.instance_variable_get(:@transport)

      expect(transport).to be_a(Manceps::Transport::Stdio)
    end

    it 'uses Stdio when args: keyword is provided even with URL-like string' do
      client = described_class.new('https-server', args: ['--port', '3000'])
      transport = client.instance_variable_get(:@transport)

      expect(transport).to be_a(Manceps::Transport::Stdio)
    end

    it 'passes env to Stdio transport' do
      client = described_class.new('my-server', env: { 'API_KEY' => 'secret' })
      transport = client.instance_variable_get(:@transport)

      expect(transport).to be_a(Manceps::Transport::Stdio)
    end
  end

  describe 'pagination' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'follows nextCursor until nil' do
      # First page: returns one tool with a cursor
      stub_request(:post, url)
        .with(body: hash_including('method' => 'tools/list', 'params' => {}))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({
                                jsonrpc: '2.0', id: 2,
                                result: {
                                  tools: [{ name: 'tool_a', description: 'First', inputSchema: { type: 'object' } }],
                                  nextCursor: 'page2'
                                }
                              })
        )

      # Second page: returns another tool with no cursor
      stub_request(:post, url)
        .with(body: hash_including('method' => 'tools/list', 'params' => { 'cursor' => 'page2' }))
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: JSON.generate({
                                jsonrpc: '2.0', id: 3,
                                result: {
                                  tools: [{ name: 'tool_b', description: 'Second', inputSchema: { type: 'object' } }]
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

  describe '#tasks' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    let(:json_headers) { { 'Content-Type' => 'application/json' } }

    it 'returns an array of Task objects' do
      stub_request(:post, url)
        .with(body: hash_including('method' => 'tasks/list'))
        .to_return(
          status: 200,
          headers: json_headers,
          body: JSON.generate({
                                jsonrpc: '2.0', id: 2,
                                result: {
                                  tasks: [
                                    { id: 'task-1', status: 'running' },
                                    { id: 'task-2', status: 'completed',
                                      result: { content: [{ type: 'text', text: 'done' }] } }
                                  ]
                                }
                              })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      tasks = client.tasks

      expect(tasks.length).to eq(2)
      expect(tasks).to all(be_a(Manceps::Task))
      expect(tasks.first.id).to eq('task-1')
      expect(tasks.first.status).to eq('running')
      expect(tasks.last.id).to eq('task-2')
      expect(tasks.last.completed?).to be true
    end

    it 'returns empty array when server has no tasks' do
      stub_request(:post, url)
        .with(body: hash_including('method' => 'tasks/list'))
        .to_return(
          status: 200,
          headers: json_headers,
          body: JSON.generate({ jsonrpc: '2.0', id: 2, result: { tasks: [] } })
        )

      client = described_class.new(url, auth: auth)
      client.connect

      expect(client.tasks).to eq([])
    end
  end

  describe '#get_task' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    let(:json_headers) { { 'Content-Type' => 'application/json' } }

    it 'sends tasks/get and returns a Task' do
      stub_request(:post, url)
        .with(body: hash_including(
          'method' => 'tasks/get',
          'params' => hash_including('taskId' => 'task-1')
        ))
        .to_return(
          status: 200,
          headers: json_headers,
          body: JSON.generate({
                                jsonrpc: '2.0', id: 2,
                                result: { id: 'task-1', status: 'completed', result: { content: [{ type: 'text', text: 'done' }] } }
                              })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      task = client.get_task('task-1')

      expect(task).to be_a(Manceps::Task)
      expect(task.id).to eq('task-1')
      expect(task.completed?).to be true
    end
  end

  describe '#cancel_task' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    let(:json_headers) { { 'Content-Type' => 'application/json' } }

    it 'sends tasks/cancel and returns true' do
      cancel_stub = stub_request(:post, url)
                    .with(body: hash_including(
                      'method' => 'tasks/cancel',
                      'params' => hash_including('taskId' => 'task-1')
                    ))
                    .to_return(
                      status: 200,
                      headers: json_headers,
                      body: JSON.generate({ jsonrpc: '2.0', id: 2, result: {} })
                    )

      client = described_class.new(url, auth: auth)
      client.connect
      result = client.cancel_task('task-1')

      expect(result).to be true
      expect(cancel_stub).to have_been_requested
    end
  end

  describe '#await_task' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    let(:json_headers) { { 'Content-Type' => 'application/json' } }

    it 'polls until the task is done and returns the completed task' do
      call_count = 0
      stub_request(:post, url)
        .with(body: hash_including('method' => 'tasks/get'))
        .to_return do |_request|
          call_count += 1
          if call_count == 1
            {
              status: 200,
              headers: json_headers,
              body: JSON.generate({ jsonrpc: '2.0', id: call_count + 1, result: { id: 'task-1', status: 'running' } })
            }
          else
            {
              status: 200,
              headers: json_headers,
              body: JSON.generate({ jsonrpc: '2.0', id: call_count + 1,
                                    result: { id: 'task-1', status: 'completed', result: { content: [{ type: 'text', text: 'done' }] } } })
            }
          end
        end

      client = described_class.new(url, auth: auth)
      client.connect
      allow(client).to receive(:sleep)

      task = client.await_task('task-1')

      expect(task).to be_a(Manceps::Task)
      expect(task.completed?).to be true
      expect(call_count).to eq(2)
    end

    it 'raises TimeoutError when timeout is exceeded' do
      stub_request(:post, url)
        .with(body: hash_including('method' => 'tasks/get'))
        .to_return(
          status: 200,
          headers: json_headers,
          body: JSON.generate({ jsonrpc: '2.0', id: 2, result: { id: 'task-1', status: 'running' } })
        )

      client = described_class.new(url, auth: auth)
      client.connect
      allow(client).to receive(:sleep)

      # Freeze time: first call at T=0, after sleep the deadline check sees T > deadline
      now = Time.now
      allow(Time).to receive(:now).and_return(now, now + 5)

      expect do
        client.await_task('task-1', timeout: 2)
      end.to raise_error(Manceps::TimeoutError, /task-1.*did not complete within 2 seconds/)
    end

    it 'returns immediately when task is already done' do
      stub_request(:post, url)
        .with(body: hash_including('method' => 'tasks/get'))
        .to_return(
          status: 200,
          headers: json_headers,
          body: JSON.generate({ jsonrpc: '2.0', id: 2,
                                result: { id: 'task-1', status: 'failed', error: { message: 'boom' } } })
        )

      client = described_class.new(url, auth: auth)
      client.connect

      task = client.await_task('task-1')

      expect(task.failed?).to be true
      expect(task.done?).to be true
    end
  end

  describe '#on_elicitation' do
    it 'registers an elicitation handler' do
      client = described_class.new(url, auth: auth)
      client.on_elicitation { |_e| Manceps::Elicitation.accept({ 'key' => 'value' }) }

      handler = client.instance_variable_get(:@elicitation_handler)
      expect(handler).to be_a(Proc)
    end
  end

  describe 'elicitation capability' do
    it 'includes elicitation capability when handler is set' do
      client = described_class.new(url, auth: auth)
      client.on_elicitation { |_e| Manceps::Elicitation.decline }

      caps = client.send(:client_capabilities)
      expect(caps).to eq('elicitation' => { 'form' => {} })
    end

    it 'does not include elicitation capability when no handler is set' do
      client = described_class.new(url, auth: auth)

      caps = client.send(:client_capabilities)
      expect(caps).to eq({})
    end

    it 'sends elicitation capability in initialize request when handler is registered' do
      init_stub = stub_request(:post, url)
                  .with(
                    body: hash_including(
                      'method' => 'initialize',
                      'params' => hash_including(
                        'capabilities' => { 'elicitation' => { 'form' => {} } }
                      )
                    ),
                    headers: { 'Authorization' => 'Bearer test-token' }
                  )
                  .to_return(
                    status: 200,
                    headers: init_response_headers,
                    body: init_response_body
                  )
      stub_initialized_notification

      client = described_class.new(url, auth: auth)
      client.on_elicitation { |_e| Manceps::Elicitation.decline }
      client.connect

      expect(init_stub).to have_been_requested
    end
  end

  describe 'handle_server_request (elicitation)' do
    before do
      stub_initialize
      stub_initialized_notification
    end

    it 'calls the elicitation handler and sends a response' do
      client = described_class.new(url, auth: auth)
      client.connect

      received_elicitation = nil
      client.on_elicitation do |e|
        received_elicitation = e
        Manceps::Elicitation.accept({ 'api_key' => 'sk-123' })
      end

      response_stub = stub_request(:post, url)
                      .with(body: hash_including(
                        'jsonrpc' => '2.0',
                        'id' => 'req-42',
                        'result' => { 'action' => 'accept', 'content' => { 'api_key' => 'sk-123' } }
                      ))
                      .to_return(status: 202)

      server_request = {
        'jsonrpc' => '2.0',
        'id' => 'req-42',
        'method' => 'elicitation/create',
        'params' => {
          'id' => 'elicit-1',
          'message' => 'Enter your API key',
          'requestedSchema' => { 'type' => 'object' }
        }
      }

      client.send(:handle_server_request, server_request)

      expect(received_elicitation).to be_a(Manceps::Elicitation)
      expect(received_elicitation.message).to eq('Enter your API key')
      expect(response_stub).to have_been_requested
    end

    it 'does nothing when no elicitation handler is set' do
      client = described_class.new(url, auth: auth)
      client.connect

      server_request = {
        'jsonrpc' => '2.0',
        'id' => 'req-42',
        'method' => 'elicitation/create',
        'params' => { 'id' => 'elicit-1', 'message' => 'Enter your key' }
      }

      expect { client.send(:handle_server_request, server_request) }.not_to raise_error
    end
  end
end
