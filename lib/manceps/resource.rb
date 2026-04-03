module Manceps
  class Resource
    attr_reader :uri, :name, :description, :mime_type, :annotations

    def initialize(data)
      @uri = data["uri"]
      @name = data["name"]
      @description = data["description"]
      @mime_type = data["mimeType"]
      @annotations = data["annotations"]
    end
  end
end
