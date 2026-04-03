require "httpx"
require "json"

module Manceps
  module Transport
    class StreamableHTTP < Base
      def initialize(url, auth:, timeout: nil)
        @url = url
        @auth = auth
        @session_id = nil

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
        handle_error_response(response)
        capture_session_id(response)
        parse_response(response)
      end

      def notify(body)
        response = @http.post(@url, headers: base_headers, body: JSON.generate(body))
        handle_error_response(response) unless response.status == 202
      end

      def terminate_session(session_id)
        headers = {}
        headers["mcp-session-id"] = session_id
        @auth.apply(headers)
        @http.delete(@url, headers: headers) rescue nil # 405 is acceptable per spec
      end

      def close
        @http.close if @http.respond_to?(:close)
        @session_id = nil
      end

      private

      def base_headers
        headers = {
          "content-type" => "application/json",
          "accept" => "application/json, text/event-stream"
        }
        headers["mcp-session-id"] = @session_id if @session_id
        @auth.apply(headers)
        headers
      end

      def parse_response(response)
        body = response.body.to_s
        content_type = response.content_type.mime_type

        if content_type.include?("text/event-stream")
          SSEParser.extract_json(body)
        else
          JSON.parse(body)
        end
      end

      def capture_session_id(response)
        sid = response.headers["mcp-session-id"]
        @session_id = sid if sid
      end

      def handle_error_response(response)
        return if response.status < 400

        case response.status
        when 401
          raise AuthenticationError, "Server returned 401: #{response.body}"
        when 404
          raise SessionExpiredError, "Session expired (404)"
        else
          raise ConnectionError, "HTTP #{response.status}: #{response.body}"
        end
      end
    end
  end
end
