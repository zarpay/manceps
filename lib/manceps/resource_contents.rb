# frozen_string_literal: true

module Manceps
  class ResourceContents
    attr_reader :contents

    def initialize(data)
      @contents = (data['contents'] || []).map { |c| Content.new(c) }
    end

    def text
      contents.select(&:text?).map(&:text).join("\n")
    end
  end
end
