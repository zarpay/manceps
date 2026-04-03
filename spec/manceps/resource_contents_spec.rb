require "spec_helper"

RSpec.describe Manceps::ResourceContents do
  it "parses contents array" do
    data = {
      "contents" => [
        { "type" => "text", "text" => "Hello world", "uri" => "file:///a.txt", "mimeType" => "text/plain" },
        { "type" => "text", "text" => "Second line", "uri" => "file:///b.txt", "mimeType" => "text/plain" }
      ]
    }

    result = described_class.new(data)

    expect(result.contents.length).to eq(2)
    expect(result.contents).to all(be_a(Manceps::Content))
    expect(result.contents.first.text).to eq("Hello world")
    expect(result.contents.last.text).to eq("Second line")
  end

  it "joins text content with newlines" do
    data = {
      "contents" => [
        { "type" => "text", "text" => "Line 1" },
        { "type" => "text", "text" => "Line 2" }
      ]
    }

    result = described_class.new(data)

    expect(result.text).to eq("Line 1\nLine 2")
  end

  it "filters non-text content from text()" do
    data = {
      "contents" => [
        { "type" => "text", "text" => "Readable" },
        { "type" => "image", "data" => "base64data", "mimeType" => "image/png" }
      ]
    }

    result = described_class.new(data)

    expect(result.text).to eq("Readable")
  end

  it "handles empty contents" do
    result = described_class.new({})

    expect(result.contents).to eq([])
    expect(result.text).to eq("")
  end
end
