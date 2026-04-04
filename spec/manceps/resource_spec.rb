require "spec_helper"

RSpec.describe Manceps::Resource do
  it "initializes from hash data" do
    data = {
      "uri" => "file:///readme.md",
      "name" => "README",
      "description" => "Project readme",
      "mimeType" => "text/markdown",
      "annotations" => { "audience" => ["developer"] }
    }

    resource = described_class.new(data)

    expect(resource.uri).to eq("file:///readme.md")
    expect(resource.name).to eq("README")
    expect(resource.description).to eq("Project readme")
    expect(resource.mime_type).to eq("text/markdown")
    expect(resource.annotations).to eq({ "audience" => ["developer"] })
  end

  it "parses title when present" do
    data = {
      "uri" => "file:///readme.md",
      "name" => "README",
      "title" => "Project README File"
    }

    resource = described_class.new(data)

    expect(resource.title).to eq("Project README File")
  end

  it "handles missing optional fields" do
    data = { "uri" => "file:///data.json", "name" => "Data" }

    resource = described_class.new(data)

    expect(resource.uri).to eq("file:///data.json")
    expect(resource.name).to eq("Data")
    expect(resource.description).to be_nil
    expect(resource.mime_type).to be_nil
    expect(resource.annotations).to be_nil
    expect(resource.title).to be_nil
  end
end
