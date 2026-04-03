module Manceps
  module Transport
    class Base
      def request(body)
        raise NotImplementedError
      end

      def request_streaming(body, &block)
        raise NotImplementedError
      end

      def notify(body)
        raise NotImplementedError
      end

      def terminate_session(session_id)
        raise NotImplementedError
      end

      def close
        raise NotImplementedError
      end
    end
  end
end
