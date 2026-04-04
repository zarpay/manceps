require "spec_helper"

RSpec.describe Manceps::ToolResult do
  describe "parsing content" do
    it "parses content array into Content objects" do
      result = described_class.new(
        "content" => [
          {"type" => "text", "text" => "Hello"},
          {"type" => "image", "data" => "base64==", "mimeType" => "image/png"}
        ]
      )

      expect(result.content.length).to eq(2)
      expect(result.content[0]).to be_a(Manceps::Content)
      expect(result.content[0].text).to eq("Hello")
      expect(result.content[1].mime_type).to eq("image/png")
    end
  end

  describe "#text" do
    it "joins text content" do
      result = described_class.new(
        "content" => [
          {"type" => "text", "text" => "line 1"},
          {"type" => "image", "data" => "base64==", "mimeType" => "image/png"},
          {"type" => "text", "text" => "line 2"}
        ]
      )

      expect(result.text).to eq("line 1\nline 2")
    end
  end

  describe "#error?" do
    it "reflects isError field" do
      error_result = described_class.new("content" => [], "isError" => true)
      ok_result = described_class.new("content" => [])

      expect(error_result).to be_error
      expect(ok_result).not_to be_error
    end
  end

  describe "#structured?" do
    it "returns true when structuredContent is present" do
      result = described_class.new(
        "content" => [{"type" => "text", "text" => "ok"}],
        "structuredContent" => {"temperature" => 72, "unit" => "F"}
      )

      expect(result).to be_structured
      expect(result.structured_content).to eq({"temperature" => 72, "unit" => "F"})
    end

    it "returns false when structuredContent is absent" do
      result = described_class.new("content" => [{"type" => "text", "text" => "ok"}])

      expect(result).not_to be_structured
      expect(result.structured_content).to be_nil
    end
  end

  describe "empty content" do
    it "handles empty content" do
      result = described_class.new("content" => [])

      expect(result.content).to eq([])
      expect(result.text).to eq("")
      expect(result).not_to be_error
    end

    it "handles missing content key" do
      result = described_class.new({})

      expect(result.content).to eq([])
    end
  end
end
