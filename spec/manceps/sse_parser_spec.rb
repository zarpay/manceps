# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Manceps::SSEParser do
  describe '.extract_json' do
    it 'parses a single data line' do
      body = "data: {\"jsonrpc\":\"2.0\",\"id\":1}\n"

      result = described_class.extract_json(body)
      expect(result).to eq('jsonrpc' => '2.0', 'id' => 1)
    end

    it 'joins multiple data lines' do
      body = "data: {\"jsonrpc\":\"2.0\",\n" \
             "data: \"id\":1}\n"

      result = described_class.extract_json(body)
      expect(result).to eq('jsonrpc' => '2.0', 'id' => 1)
    end

    it 'handles event/id prefixed streams by extracting only data lines' do
      body = "event: message\nid: 42\ndata: {\"ok\":true}\n"

      result = described_class.extract_json(body)
      expect(result).to eq('ok' => true)
    end

    it 'returns nil for empty body' do
      expect(described_class.extract_json('')).to be_nil
      expect(described_class.extract_json(nil)).to be_nil
    end

    it 'returns nil when there are no data lines' do
      expect(described_class.extract_json("event: ping\nid: 1\n")).to be_nil
    end
  end

  describe '.parse_events' do
    it 'returns an array of events with id, event, and data' do
      body = "event: message\nid: 1\ndata: hello\n\n"

      events = described_class.parse_events(body)
      expect(events.length).to eq(1)
      expect(events[0]).to eq(id: '1', event: 'message', data: 'hello')
    end

    it 'handles blank line boundaries between events' do
      body = "data: first\n\ndata: second\n\n"

      events = described_class.parse_events(body)
      expect(events.length).to eq(2)
      expect(events[0][:data]).to eq('first')
      expect(events[1][:data]).to eq('second')
    end

    it 'handles trailing event without final blank line' do
      body = 'data: trailing'

      events = described_class.parse_events(body)
      expect(events.length).to eq(1)
      expect(events[0][:data]).to eq('trailing')
    end

    it 'returns empty array for empty body' do
      expect(described_class.parse_events('')).to eq([])
      expect(described_class.parse_events(nil)).to eq([])
    end
  end
end
