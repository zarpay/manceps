require "spec_helper"

RSpec.describe Manceps::Prompt do
  let(:data) do
    {
      "name" => "code_review",
      "description" => "Review code for best practices",
      "arguments" => [
        { "name" => "code", "description" => "The code to review", "required" => true },
        { "name" => "language", "description" => "Programming language", "required" => false }
      ]
    }
  end

  describe "initialization" do
    it "initializes from hash data" do
      prompt = described_class.new(data)

      expect(prompt.name).to eq("code_review")
      expect(prompt.description).to eq("Review code for best practices")
    end

    it "parses arguments array" do
      prompt = described_class.new(data)

      expect(prompt.arguments.length).to eq(2)
      expect(prompt.arguments[0].name).to eq("code")
      expect(prompt.arguments[0].description).to eq("The code to review")
      expect(prompt.arguments[1].name).to eq("language")
    end

    it "handles missing arguments key" do
      prompt = described_class.new("name" => "simple", "description" => "A simple prompt")

      expect(prompt.arguments).to eq([])
    end
  end

  describe Manceps::Prompt::Argument do
    it "required? returns true when required" do
      arg = described_class.new("name" => "code", "description" => "Code", "required" => true)

      expect(arg).to be_required
    end

    it "required? returns false when not required" do
      arg = described_class.new("name" => "lang", "description" => "Language", "required" => false)

      expect(arg).not_to be_required
    end

    it "defaults required to false when missing" do
      arg = described_class.new("name" => "opt", "description" => "Optional")

      expect(arg).not_to be_required
    end
  end
end
