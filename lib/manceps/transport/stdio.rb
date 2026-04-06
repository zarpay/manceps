# frozen_string_literal: true

require 'open3'
require 'json'

module Manceps
  module Transport
    # Stdio transport: communicates with a local subprocess via stdin/stdout.
    class Stdio < Base
      def initialize(command, args: [], env: {})
        super()
        @command = command
        @args = args
        @env = env
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thread = nil
        @mutex = Mutex.new
        @notification_callback = nil
      end

      def open
        close if @wait_thread # Clean up any existing process

        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(@env, @command, *@args)

        at_exit { close }

        self
      end

      def request(body)
        @mutex.synchronize do
          write_message(body)
          read_response
        end
      end

      def notify(body)
        @mutex.synchronize do
          write_message(body)
        end
      end

      def terminate_session(_session_id)
        # No-op for stdio -- session ends when the process exits
      end

      def listen(&block)
        raise ConnectionError, 'Stdio transport not open' unless @stdout

        loop do
          line = @stdout.gets
          break if line.nil?

          parsed = begin
            JSON.parse(line)
          rescue StandardError
            next
          end
          block.call(parsed) if parsed['method']
        end
      end

      def close
        return unless @wait_thread

        begin
          @stdin&.close
        rescue StandardError
          nil
        end

        if @wait_thread.alive?
          begin
            Process.kill('TERM', @wait_thread.pid)
          rescue StandardError
            nil
          end

          unless @wait_thread.join(5)
            begin
              Process.kill('KILL', @wait_thread.pid)
            rescue StandardError
              nil
            end
            begin
              @wait_thread.join(1)
            rescue StandardError
              nil
            end
          end
        end

        begin
          @stdout&.close
        rescue StandardError
          nil
        end
        begin
          @stderr&.close
        rescue StandardError
          nil
        end
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thread = nil
      end

      private

      def write_message(body)
        raise ConnectionError, 'Stdio transport not open' unless @stdin

        json = JSON.generate(body)
        @stdin.write("#{json}\n")
        @stdin.flush
      rescue Errno::EPIPE
        raise ConnectionError, 'Process exited unexpectedly'
      end

      def read_response
        raise ConnectionError, 'Stdio transport not open' unless @stdout

        loop do
          line = @stdout.gets
          raise ConnectionError, 'Process exited unexpectedly' if line.nil?

          parsed = JSON.parse(line)

          return parsed unless parsed['method'] && !parsed.key?('id')

          # This is a server-initiated notification; dispatch and keep reading
          @notification_callback&.call(parsed)
        end
      rescue JSON::ParserError => e
        raise ProtocolError, "Invalid JSON from process: #{e.message}"
      end
    end
  end
end
