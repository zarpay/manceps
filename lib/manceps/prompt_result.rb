# frozen_string_literal: true

module Manceps
  # Result of a prompt/get request.
  class PromptResult
    attr_reader :description, :messages

    def initialize(data)
      @description = data['description']
      @messages = (data['messages'] || []).map { |m| Message.new(m) }
    end

    # A single message within a prompt result.
    class Message
      attr_reader :role, :content

      def initialize(data)
        @role = data['role']
        @content = Content.new(data['content']) if data['content']
      end

      def text
        content&.text
      end
    end
  end
end
