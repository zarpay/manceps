# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Manceps::Auth::ApiKeyHeader do
  describe '#apply' do
    it 'sets the custom header name (lowercased) with the key value' do
      auth = described_class.new('X-Api-Key', 'secret-key')
      headers = {}

      auth.apply(headers)

      expect(headers['x-api-key']).to eq('secret-key')
    end
  end
end
