# frozen_string_literal: true

module Manceps
  # An MCP resource definition.
  class Resource
    attr_reader :uri, :name, :description, :mime_type, :annotations, :title

    def initialize(data)
      @uri = data['uri']
      @name = data['name']
      @description = data['description']
      @mime_type = data['mimeType']
      @annotations = data['annotations']
      @title = data['title']
    end
  end
end
