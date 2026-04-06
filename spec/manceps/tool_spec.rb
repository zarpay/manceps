# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Manceps::Tool do
  let(:data) do
    {
      'name' => 'get_weather',
      'description' => 'Get current weather for a city',
      'inputSchema' => { 'type' => 'object', 'properties' => { 'city' => { 'type' => 'string' } } },
      'annotations' => { 'readOnly' => true }
    }
  end

  describe 'initialization' do
    it 'initializes from hash data' do
      tool = described_class.new(data)

      expect(tool.name).to eq('get_weather')
      expect(tool.description).to eq('Get current weather for a city')
      expect(tool.input_schema).to eq('type' => 'object', 'properties' => { 'city' => { 'type' => 'string' } })
      expect(tool.annotations).to eq('readOnly' => true)
    end

    it 'parses title when present' do
      tool = described_class.new(data.merge('title' => 'Weather Lookup'))

      expect(tool.title).to eq('Weather Lookup')
    end

    it 'parses outputSchema when present' do
      schema = { 'type' => 'object', 'properties' => { 'temp' => { 'type' => 'number' } } }
      tool = described_class.new(data.merge('outputSchema' => schema))

      expect(tool.output_schema).to eq(schema)
    end

    it 'defaults title and outputSchema to nil when absent' do
      tool = described_class.new(data)

      expect(tool.title).to be_nil
      expect(tool.output_schema).to be_nil
    end
  end

  describe '#to_h' do
    it 'returns the hash representation' do
      tool = described_class.new(data)

      expect(tool.to_h).to eq(
        'name' => 'get_weather',
        'description' => 'Get current weather for a city',
        'inputSchema' => { 'type' => 'object', 'properties' => { 'city' => { 'type' => 'string' } } }
      )
    end

    it 'includes title when present' do
      tool = described_class.new(data.merge('title' => 'Weather Lookup'))

      expect(tool.to_h['title']).to eq('Weather Lookup')
    end

    it 'omits title when nil' do
      tool = described_class.new(data)

      expect(tool.to_h).not_to have_key('title')
    end

    it 'includes outputSchema when present' do
      schema = { 'type' => 'object', 'properties' => { 'temp' => { 'type' => 'number' } } }
      tool = described_class.new(data.merge('outputSchema' => schema))

      expect(tool.to_h['outputSchema']).to eq(schema)
    end

    it 'omits outputSchema when nil' do
      tool = described_class.new(data)

      expect(tool.to_h).not_to have_key('outputSchema')
    end
  end
end
