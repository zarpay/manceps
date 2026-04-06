# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Manceps::Auth::Bearer do
  describe '#apply' do
    it 'sets authorization header with Bearer prefix' do
      auth = described_class.new('my-token-123')
      headers = {}

      auth.apply(headers)

      expect(headers['authorization']).to eq('Bearer my-token-123')
    end
  end
end
