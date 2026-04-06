# frozen_string_literal: true

module Manceps
  # An MCP prompt definition.
  class Prompt
    attr_reader :name, :description, :arguments, :title

    def initialize(data)
      @name = data['name']
      @description = data['description']
      @title = data['title']
      @arguments = (data['arguments'] || []).map { |a| Argument.new(a) }
    end

    # A prompt argument definition.
    class Argument
      attr_reader :name, :description, :required

      def initialize(data)
        @name = data['name']
        @description = data['description']
        @required = data['required'] || false
      end

      def required?
        required
      end
    end
  end
end
