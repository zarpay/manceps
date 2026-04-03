module Manceps
  class Tool
    attr_reader :name, :description, :input_schema, :annotations

    def initialize(data)
      @name = data["name"]
      @description = data["description"]
      @input_schema = data["inputSchema"]
      @annotations = data["annotations"]
    end

    def to_h
      { "name" => name, "description" => description, "inputSchema" => input_schema }
    end
  end
end
