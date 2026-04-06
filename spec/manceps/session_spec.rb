# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Manceps::Session do
  subject(:session) { described_class.new }

  it 'starts inactive with nil id' do
    expect(session.id).to be_nil
    expect(session).not_to be_active
  end

  describe '#next_id' do
    it 'increments monotonically' do
      expect(session.next_id).to eq(1)
      expect(session.next_id).to eq(2)
      expect(session.next_id).to eq(3)
    end
  end

  describe '#establish' do
    it 'extracts session data from symbol-keyed response' do
      response = {
        sessionId: 'sess-abc',
        result: {
          capabilities: { tools: {} },
          protocolVersion: '2025-03-26',
          serverInfo: { name: 'TestServer', version: '1.0' }
        }
      }

      session.establish(response)

      expect(session.id).to eq('sess-abc')
      expect(session.capabilities).to eq(tools: {})
      expect(session.protocol_version).to eq('2025-03-26')
      expect(session.server_info).to eq(name: 'TestServer', version: '1.0')
    end

    it 'extracts session data from string-keyed response' do
      response = {
        'sessionId' => 'sess-def',
        'result' => {
          'capabilities' => { 'tools' => {} },
          'protocolVersion' => '2025-03-26',
          'serverInfo' => { 'name' => 'TestServer', 'version' => '1.0' }
        }
      }

      session.establish(response)

      expect(session.id).to eq('sess-def')
      expect(session.capabilities).to eq('tools' => {})
      expect(session.protocol_version).to eq('2025-03-26')
      expect(session.server_info).to eq('name' => 'TestServer', 'version' => '1.0')
    end

    it 'is active after establish' do
      session.establish(sessionId: 's1', result: {})

      expect(session).to be_active
    end

    it 'defaults to empty hash when result is missing' do
      session.establish({})

      expect(session).to be_active
      expect(session.id).to be_nil
      expect(session.capabilities).to eq({})
      expect(session.protocol_version).to be_nil
      expect(session.server_info).to be_nil
    end
  end

  describe '#server_supports?' do
    it 'returns true when capability exists as string key' do
      session.establish(sessionId: 's1', result: { 'capabilities' => { 'tools' => {} } })

      expect(session.server_supports?('tools')).to be true
    end

    it 'returns true when capability exists as symbol key' do
      session.establish(sessionId: 's1', result: { capabilities: { tools: {} } })

      expect(session.server_supports?(:tools)).to be true
    end

    it 'returns false when capability does not exist' do
      session.establish(sessionId: 's1', result: { capabilities: { tools: {} } })

      expect(session.server_supports?(:prompts)).to be false
    end
  end

  describe '#reset' do
    it 'clears all state' do
      session.establish(sessionId: 's1', result: { capabilities: { tools: {} } })
      session.next_id

      session.reset

      expect(session.id).to be_nil
      expect(session.capabilities).to eq({})
      expect(session.protocol_version).to be_nil
      expect(session.server_info).to be_nil
      expect(session).not_to be_active
      expect(session.next_id).to eq(1)
    end
  end
end
