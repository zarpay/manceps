# frozen_string_literal: true

module Manceps
  # A single content item returned by an MCP tool or prompt.
  class Content
    attr_reader :type, :text, :data, :mime_type, :uri, :resource

    def initialize(data)
      @type = data['type']
      @text = data['text']
      @data = data['data']        # base64 for image/audio
      @mime_type = data['mimeType']
      @uri = data['uri']          # for resource content
      @resource = data['resource'] # for resource_link type
    end

    def text?
      type == 'text'
    end

    def image?
      type == 'image'
    end

    def resource?
      type == 'resource'
    end

    def resource_link?
      type == 'resource_link'
    end
  end
end
