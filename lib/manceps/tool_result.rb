# frozen_string_literal: true

module Manceps
  class ToolResult
    attr_reader :content, :is_error, :structured_content

    def initialize(data)
      @content = (data['content'] || []).map { |c| Content.new(c) }
      @is_error = data['isError'] || false
      @structured_content = data['structuredContent']
    end

    def error?
      is_error
    end

    def text
      content.select(&:text?).map(&:text).join("\n")
    end

    def structured?
      !structured_content.nil?
    end
  end
end
