module Manceps
  class Elicitation
    attr_reader :id, :message, :requested_schema

    def initialize(data)
      @id = data["id"]
      @message = data["message"]
      @requested_schema = data["requestedSchema"]
    end

    def self.accept(content)
      { action: "accept", content: content }
    end

    def self.decline
      { action: "decline" }
    end

    def self.cancel
      { action: "cancel" }
    end
  end
end
