require "spec_helper"

RSpec.describe Manceps::Tool do
  let(:data) do
    {
      "name" => "get_weather",
      "description" => "Get current weather for a city",
      "inputSchema" => {"type" => "object", "properties" => {"city" => {"type" => "string"}}},
      "annotations" => {"readOnly" => true}
    }
  end

  describe "initialization" do
    it "initializes from hash data" do
      tool = described_class.new(data)

      expect(tool.name).to eq("get_weather")
      expect(tool.description).to eq("Get current weather for a city")
      expect(tool.input_schema).to eq("type" => "object", "properties" => {"city" => {"type" => "string"}})
      expect(tool.annotations).to eq("readOnly" => true)
    end
  end

  describe "#to_h" do
    it "returns the hash representation" do
      tool = described_class.new(data)

      expect(tool.to_h).to eq(
        "name" => "get_weather",
        "description" => "Get current weather for a city",
        "inputSchema" => {"type" => "object", "properties" => {"city" => {"type" => "string"}}}
      )
    end
  end
end
