require "open3"
require "json"

module Manceps
  module Transport
    class Stdio < Base
      def initialize(command, args: [], env: {})
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
        close if @wait_thread  # Clean up any existing process

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
        raise ConnectionError, "Stdio transport not open" unless @stdout

        loop do
          line = @stdout.gets
          break if line.nil?
          parsed = JSON.parse(line) rescue next
          block.call(parsed) if parsed["method"]
        end
      end

      def close
        return unless @wait_thread

        @stdin&.close rescue nil

        if @wait_thread.alive?
          Process.kill("TERM", @wait_thread.pid) rescue nil

          unless @wait_thread.join(5)
            Process.kill("KILL", @wait_thread.pid) rescue nil
            @wait_thread.join(1) rescue nil
          end
        end

        @stdout&.close rescue nil
        @stderr&.close rescue nil
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thread = nil
      end

      private

      def write_message(body)
        raise ConnectionError, "Stdio transport not open" unless @stdin

        json = JSON.generate(body)
        @stdin.write(json + "\n")
        @stdin.flush
      rescue Errno::EPIPE
        raise ConnectionError, "Process exited unexpectedly"
      end

      def read_response
        raise ConnectionError, "Stdio transport not open" unless @stdout

        loop do
          line = @stdout.gets
          raise ConnectionError, "Process exited unexpectedly" if line.nil?

          parsed = JSON.parse(line)

          if parsed["method"] && !parsed.key?("id")
            # This is a server-initiated notification; dispatch and keep reading
            @notification_callback&.call(parsed)
          else
            return parsed
          end
        end
      rescue JSON::ParserError => e
        raise ProtocolError.new("Invalid JSON from process: #{e.message}")
      end
    end
  end
end
