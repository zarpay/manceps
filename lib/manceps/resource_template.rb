module Manceps
  class ResourceTemplate
    attr_reader :uri_template, :name, :description, :mime_type, :annotations

    def initialize(data)
      @uri_template = data["uriTemplate"]
      @name = data["name"]
      @description = data["description"]
      @mime_type = data["mimeType"]
      @annotations = data["annotations"]
    end
  end
end
