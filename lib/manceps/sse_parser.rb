# frozen_string_literal: true

require 'json'

module Manceps
  module SSEParser
    module_function

    def extract_json(body)
      return nil if body.nil? || body.strip.empty?

      data_lines = body.each_line.filter_map do |line|
        line.strip.start_with?('data:') ? line.strip.sub(/\Adata:\s?/, '') : nil
      end

      return nil if data_lines.empty?

      JSON.parse(data_lines.join, symbolize_names: true)
    end

    def parse_events(body)
      return [] if body.nil? || body.strip.empty?

      events = []
      current = { id: nil, event: nil, data: [] }

      body.each_line do |raw_line|
        line = raw_line.chomp

        if line.empty?
          unless current[:data].empty?
            events << {
              id: current[:id],
              event: current[:event],
              data: current[:data].join("\n")
            }
          end
          current = { id: nil, event: nil, data: [] }
          next
        end

        if line.start_with?('id:')
          current[:id] = line.sub(/\Aid:\s?/, '')
        elsif line.start_with?('event:')
          current[:event] = line.sub(/\Aevent:\s?/, '')
        elsif line.start_with?('data:')
          current[:data] << line.sub(/\Adata:\s?/, '')
        end
      end

      # Flush any trailing event without a final blank line
      unless current[:data].empty?
        events << {
          id: current[:id],
          event: current[:event],
          data: current[:data].join("\n")
        }
      end

      events
    end
  end
end
