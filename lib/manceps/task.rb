# frozen_string_literal: true

module Manceps
  class Task
    attr_reader :id, :status, :result, :error, :metadata

    STATUSES = %w[pending running completed failed cancelled].freeze

    def initialize(data)
      @id = data['id']
      @status = data['status']
      @result = data['result']
      @error = data['error']
      @metadata = data['metadata'] || data['_meta']
    end

    def pending?
      status == 'pending'
    end

    def running?
      status == 'running'
    end

    def completed?
      status == 'completed'
    end

    def failed?
      status == 'failed'
    end

    def cancelled?
      status == 'cancelled'
    end

    def done?
      completed? || failed? || cancelled?
    end
  end
end
