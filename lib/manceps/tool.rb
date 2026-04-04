module Manceps
  class Tool
    attr_reader :name, :description, :input_schema, :output_schema, :annotations, :title

    def initialize(data)
      @name = data["name"]
      @description = data["description"]
      @title = data["title"]
      @input_schema = data["inputSchema"]
      @output_schema = data["outputSchema"]
      @annotations = data["annotations"]
    end

    def to_h
      h = { "name" => name, "description" => description, "inputSchema" => input_schema }
      h["title"] = title if title
      h["outputSchema"] = output_schema if output_schema
      h
    end
  end
end
