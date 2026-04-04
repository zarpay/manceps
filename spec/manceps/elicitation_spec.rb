require "spec_helper"

RSpec.describe Manceps::Elicitation do
  describe "#initialize" do
    it "parses id, message, and requestedSchema from hash data" do
      data = {
        "id" => "elicit-1",
        "message" => "What is your API key?",
        "requestedSchema" => {
          "type" => "object",
          "properties" => {
            "api_key" => { "type" => "string" }
          }
        }
      }

      elicitation = described_class.new(data)

      expect(elicitation.id).to eq("elicit-1")
      expect(elicitation.message).to eq("What is your API key?")
      expect(elicitation.requested_schema).to eq(data["requestedSchema"])
    end

    it "handles missing fields gracefully" do
      elicitation = described_class.new({})

      expect(elicitation.id).to be_nil
      expect(elicitation.message).to be_nil
      expect(elicitation.requested_schema).to be_nil
    end
  end

  describe ".accept" do
    it "returns a response hash with accept action and content" do
      result = described_class.accept({ "api_key" => "sk-123" })

      expect(result).to eq(action: "accept", content: { "api_key" => "sk-123" })
    end
  end

  describe ".decline" do
    it "returns a response hash with decline action" do
      result = described_class.decline

      expect(result).to eq(action: "decline")
    end
  end

  describe ".cancel" do
    it "returns a response hash with cancel action" do
      result = described_class.cancel

      expect(result).to eq(action: "cancel")
    end
  end
end
