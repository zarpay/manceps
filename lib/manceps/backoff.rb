# frozen_string_literal: true

module Manceps
  class Backoff
    def initialize(base: 1, max: 30, multiplier: 2, jitter: true)
      @base = base
      @max = max
      @multiplier = multiplier
      @jitter = jitter
      @attempts = 0
    end

    def next_delay
      delay = [@base * (@multiplier**@attempts), @max].min
      delay *= rand(0.5..1.0) if @jitter
      @attempts += 1
      delay
    end

    def reset
      @attempts = 0
    end
  end
end
