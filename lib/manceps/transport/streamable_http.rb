# frozen_string_literal: true

require 'httpx'
require 'json'

module Manceps
  module Transport
    class StreamableHTTP < Base
      attr_reader :session_id
      attr_writer :protocol_version

      def initialize(url, auth:, timeout: nil)
        @url = url
        @auth = auth
        @session_id = nil
        @last_event_id = nil
        @protocol_version = nil

        timeout_opts = timeout || {
          connect_timeout: Manceps.configuration.connect_timeout,
          request_timeout: Manceps.configuration.request_timeout
        }

        # httpx maintains persistent connections by default —
        # critical because MCP servers bind Mcp-Session-Id to the TCP connection
        @http = HTTPX.with(timeout: timeout_opts)
      end

      def request(body)
        response = @http.post(@url, headers: base_headers, body: JSON.generate(body))
        handle_connection_error(response)
        handle_error_response(response)
        capture_session_id(response)
        result = parse_response(response)
        track_event_ids_from_response(response)
        result
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, Errno::EHOSTUNREACH => e
        raise ConnectionError, e.message
      end

      def request_streaming(body, &block)
        response = @http.post(@url, headers: base_headers, body: JSON.generate(body))
        handle_connection_error(response)
        handle_error_response(response)
        capture_session_id(response)

        content_type = response.content_type&.mime_type.to_s

        if content_type.include?('text/event-stream')
          events = SSEParser.parse_events(response.body.to_s)
          track_event_ids(events)
          final_result = nil
          events.each do |event|
            parsed = begin
              JSON.parse(event[:data])
            rescue StandardError
              next
            end
            if parsed['result'] || parsed['error']
              final_result = parsed
            elsif block
              block.call(parsed)
            end
          end
          final_result || parse_response(response)
        else
          parse_response(response)
        end
      end

      def notify(body)
        response = @http.post(@url, headers: base_headers, body: JSON.generate(body))
        handle_connection_error(response)
        handle_error_response(response) unless response.status == 202
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, Errno::EHOSTUNREACH => e
        raise ConnectionError, e.message
      end

      def terminate_session(session_id)
        headers = {}
        headers['mcp-session-id'] = session_id
        @auth.apply(headers)
        begin
          @http.delete(@url, headers: headers)
        rescue StandardError
          nil
        end
      end

      def listen(&block)
        headers = base_headers.dup
        headers.delete('content-type')
        headers['accept'] = 'text/event-stream'

        response = @http.get(@url, headers: headers)
        handle_error_response(response)

        content_type = response.content_type&.mime_type.to_s
        return unless content_type.include?('text/event-stream')

        events = SSEParser.parse_events(response.body.to_s)
        events.each do |event|
          parsed = begin
            JSON.parse(event[:data])
          rescue StandardError
            next
          end
          block.call(parsed) if parsed['method']
        end
      end

      def close
        @http.close if @http.respond_to?(:close)
        @session_id = nil
      end

      private

      def base_headers
        headers = {
          'content-type' => 'application/json',
          'accept' => 'application/json, text/event-stream'
        }
        headers['mcp-session-id'] = @session_id if @session_id
        headers['mcp-protocol-version'] = @protocol_version if @protocol_version
        headers['last-event-id'] = @last_event_id if @last_event_id
        @auth.apply(headers)
        headers
      end

      def parse_response(response)
        body = response.body.to_s
        content_type = response.content_type&.mime_type.to_s

        if content_type.include?('text/event-stream')
          SSEParser.extract_json(body)
        else
          JSON.parse(body)
        end
      rescue JSON::ParserError => e
        raise ProtocolError, "Invalid JSON in response: #{e.message}"
      end

      def capture_session_id(response)
        sid = response.headers['mcp-session-id']
        @session_id = sid if sid
      end

      def track_event_ids(events)
        last = events.select { |e| e[:id] }.last
        @last_event_id = last[:id] if last
      end

      def track_event_ids_from_response(response)
        content_type = response.content_type&.mime_type.to_s
        return unless content_type.include?('text/event-stream')

        events = SSEParser.parse_events(response.body.to_s)
        track_event_ids(events)
      end

      def handle_connection_error(response)
        return unless response.is_a?(HTTPX::ErrorResponse)

        error = response.error
        case error
        when Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EPIPE, Errno::EHOSTUNREACH
          raise ConnectionError, error.message
        when HTTPX::TimeoutError
          raise TimeoutError, error.message
        else
          raise ConnectionError, error.message
        end
      end

      def handle_error_response(response)
        return if response.status < 400

        case response.status
        when 401
          raise AuthenticationError, "Server returned 401: #{response.body}"
        when 404
          raise SessionExpiredError, 'Session expired (404)'
        else
          raise ConnectionError, "HTTP #{response.status}: #{response.body}"
        end
      end
    end
  end
end
