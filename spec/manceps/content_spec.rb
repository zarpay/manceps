require "spec_helper"

RSpec.describe Manceps::Content do
  describe "type predicates" do
    it "text? returns true for text type" do
      content = described_class.new("type" => "text", "text" => "hello")

      expect(content).to be_text
      expect(content).not_to be_image
      expect(content).not_to be_resource
    end

    it "image? returns true for image type" do
      content = described_class.new("type" => "image", "data" => "base64==", "mimeType" => "image/png")

      expect(content).to be_image
      expect(content).not_to be_text
      expect(content).not_to be_resource
    end

    it "resource? returns true for resource type" do
      content = described_class.new("type" => "resource", "uri" => "file:///tmp/foo.txt")

      expect(content).to be_resource
      expect(content).not_to be_text
      expect(content).not_to be_image
    end
  end

  describe "field extraction" do
    it "extracts all fields from data hash" do
      content = described_class.new(
        "type" => "image",
        "text" => nil,
        "data" => "base64data",
        "mimeType" => "image/jpeg",
        "uri" => "https://example.com/image.jpg"
      )

      expect(content.type).to eq("image")
      expect(content.text).to be_nil
      expect(content.data).to eq("base64data")
      expect(content.mime_type).to eq("image/jpeg")
      expect(content.uri).to eq("https://example.com/image.jpg")
    end
  end
end
