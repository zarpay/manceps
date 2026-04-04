require "spec_helper"

RSpec.describe Manceps::ResourceTemplate do
  it "initializes from hash data" do
    data = {
      "uriTemplate" => "file:///logs/{date}.log",
      "name" => "Daily Log",
      "description" => "Log file for a given date",
      "mimeType" => "text/plain",
      "annotations" => { "audience" => ["ops"] }
    }

    template = described_class.new(data)

    expect(template.uri_template).to eq("file:///logs/{date}.log")
    expect(template.name).to eq("Daily Log")
    expect(template.description).to eq("Log file for a given date")
    expect(template.mime_type).to eq("text/plain")
    expect(template.annotations).to eq({ "audience" => ["ops"] })
  end

  it "parses title when present" do
    data = {
      "uriTemplate" => "file:///logs/{date}.log",
      "name" => "Daily Log",
      "title" => "Daily Log Files"
    }

    template = described_class.new(data)

    expect(template.title).to eq("Daily Log Files")
  end

  it "handles missing optional fields" do
    data = { "uriTemplate" => "db:///{table}", "name" => "Table" }

    template = described_class.new(data)

    expect(template.uri_template).to eq("db:///{table}")
    expect(template.name).to eq("Table")
    expect(template.description).to be_nil
    expect(template.mime_type).to be_nil
    expect(template.annotations).to be_nil
    expect(template.title).to be_nil
  end
end
