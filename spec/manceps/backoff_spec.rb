# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Manceps::Backoff do
  describe '#next_delay' do
    it 'increases exponentially' do
      backoff = described_class.new(base: 1, multiplier: 2, jitter: false)

      delays = 4.times.map { backoff.next_delay }

      expect(delays).to eq([1, 2, 4, 8])
    end

    it 'respects max delay' do
      backoff = described_class.new(base: 1, max: 5, multiplier: 2, jitter: false)

      delays = 5.times.map { backoff.next_delay }

      expect(delays).to eq([1, 2, 4, 5, 5])
    end

    it 'applies jitter when enabled' do
      backoff = described_class.new(base: 10, multiplier: 2, jitter: true)

      delays = 10.times.map { backoff.next_delay }

      # With jitter, delays should vary (not all identical to the base calculation)
      # Each delay should be between 50% and 100% of the non-jittered value
      expect(delays.uniq.size).to be > 1
    end

    it 'keeps jittered delay within expected range' do
      backoff = described_class.new(base: 10, multiplier: 1, max: 10, jitter: true)

      delays = 100.times.map { backoff.next_delay }

      delays.each do |delay|
        expect(delay).to be >= 5.0   # 10 * 0.5
        expect(delay).to be <= 10.0  # 10 * 1.0
      end
    end
  end

  describe '#reset' do
    it 'resets attempts so delays start over' do
      backoff = described_class.new(base: 1, multiplier: 2, jitter: false)

      3.times { backoff.next_delay }
      backoff.reset

      expect(backoff.next_delay).to eq(1)
    end
  end
end
