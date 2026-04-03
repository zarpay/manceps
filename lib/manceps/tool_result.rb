module Manceps
  class ToolResult
    attr_reader :content, :is_error

    def initialize(data)
      @content = (data["content"] || []).map { |c| Content.new(c) }
      @is_error = data["isError"] || false
    end

    def error?
      is_error
    end

    def text
      content.select(&:text?).map(&:text).join("\n")
    end
  end
end
