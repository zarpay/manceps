# frozen_string_literal: true

module Manceps
  class ResourceTemplate
    attr_reader :uri_template, :name, :description, :mime_type, :annotations, :title

    def initialize(data)
      @uri_template = data['uriTemplate']
      @name = data['name']
      @description = data['description']
      @mime_type = data['mimeType']
      @annotations = data['annotations']
      @title = data['title']
    end
  end
end
