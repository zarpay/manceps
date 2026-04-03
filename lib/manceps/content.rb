module Manceps
  class Content
    attr_reader :type, :text, :data, :mime_type, :uri

    def initialize(data)
      @type = data["type"]
      @text = data["text"]
      @data = data["data"]        # base64 for image/audio
      @mime_type = data["mimeType"]
      @uri = data["uri"]          # for resource content
    end

    def text?
      type == "text"
    end

    def image?
      type == "image"
    end

    def resource?
      type == "resource"
    end
  end
end
