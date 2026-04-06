# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Manceps::JsonRpc do
  describe '.request' do
    it 'returns a JSON-RPC 2.0 structure with id, method, and params' do
      result = described_class.request(1, 'tools/list', { cursor: 'abc' })

      expect(result).to eq(jsonrpc: '2.0', id: 1, method: 'tools/list', params: { cursor: 'abc' })
    end

    it 'defaults params to empty hash' do
      result = described_class.request(5, 'tools/list')

      expect(result[:params]).to eq({})
    end
  end

  describe '.notification' do
    it 'returns a structure without id' do
      result = described_class.notification('notifications/initialized', {})

      expect(result).to eq(jsonrpc: '2.0', method: 'notifications/initialized', params: {})
      expect(result).not_to have_key(:id)
    end
  end

  describe '.initialize_request' do
    it 'builds a proper MCP initialize message' do
      result = described_class.initialize_request(1)

      expect(result[:jsonrpc]).to eq('2.0')
      expect(result[:id]).to eq(1)
      expect(result[:method]).to eq('initialize')
      expect(result[:params][:protocolVersion]).to eq(Manceps.configuration.protocol_version)
      expect(result[:params][:capabilities]).to eq({})
      expect(result[:params][:clientInfo]).to eq(
        name: Manceps.configuration.client_name,
        version: Manceps.configuration.client_version
      )
    end

    it 'accepts and includes capabilities' do
      caps = { 'elicitation' => { 'form' => {} } }
      result = described_class.initialize_request(1, capabilities: caps)

      expect(result[:params][:capabilities]).to eq(caps)
    end

    it 'defaults capabilities to empty hash' do
      result = described_class.initialize_request(1)

      expect(result[:params][:capabilities]).to eq({})
    end

    it 'accepts custom client_info' do
      info = { name: 'TestClient', version: '1.0' }
      result = described_class.initialize_request(2, client_info: info)

      expect(result[:params][:clientInfo]).to eq(info)
    end

    it 'includes description in clientInfo when configured' do
      original_description = Manceps.configuration.client_description
      begin
        Manceps.configuration.client_description = 'A test MCP client'
        result = described_class.initialize_request(3)

        expect(result[:params][:clientInfo][:description]).to eq('A test MCP client')
      ensure
        Manceps.configuration.client_description = original_description
      end
    end

    it 'omits description from clientInfo when not configured' do
      original_description = Manceps.configuration.client_description
      begin
        Manceps.configuration.client_description = nil
        result = described_class.initialize_request(4)

        expect(result[:params][:clientInfo]).not_to have_key(:description)
      ensure
        Manceps.configuration.client_description = original_description
      end
    end
  end

  describe '.initialized_notification' do
    it 'returns the correct notification method' do
      result = described_class.initialized_notification

      expect(result[:method]).to eq('notifications/initialized')
      expect(result).not_to have_key(:id)
    end
  end

  describe '.response' do
    it 'builds a valid JSON-RPC 2.0 response' do
      result = described_class.response(42, { action: 'accept', content: { 'key' => 'val' } })

      expect(result).to eq(jsonrpc: '2.0', id: 42, result: { action: 'accept', content: { 'key' => 'val' } })
    end

    it 'works with a string id' do
      result = described_class.response('req-1', { status: 'ok' })

      expect(result[:jsonrpc]).to eq('2.0')
      expect(result[:id]).to eq('req-1')
      expect(result[:result]).to eq({ status: 'ok' })
    end
  end

  describe '.parse_response' do
    it 'returns data as-is for valid responses' do
      data = { jsonrpc: '2.0', id: 1, result: { tools: [] } }

      expect(described_class.parse_response(data)).to eq(data)
    end

    it 'parses JSON strings' do
      json = '{"jsonrpc":"2.0","id":1,"result":{}}'

      result = described_class.parse_response(json)
      expect(result[:jsonrpc]).to eq('2.0')
      expect(result[:id]).to eq(1)
    end

    it 'raises ProtocolError for error responses' do
      data = { jsonrpc: '2.0', id: 1, error: { code: -32_600, message: 'Invalid Request' } }

      expect { described_class.parse_response(data) }.to raise_error(Manceps::ProtocolError) do |err|
        expect(err.message).to eq('Invalid Request')
        expect(err.code).to eq(-32_600)
      end
    end

    it 'raises ProtocolError for invalid JSON-RPC version' do
      data = { jsonrpc: '1.0', id: 1, result: {} }

      expect { described_class.parse_response(data) }.to raise_error(Manceps::ProtocolError, /Invalid JSON-RPC version/)
    end
  end
end
