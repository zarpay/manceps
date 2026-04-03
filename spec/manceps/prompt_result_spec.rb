require "spec_helper"

RSpec.describe Manceps::PromptResult do
  describe "initialization" do
    it "parses messages array" do
      result = described_class.new(
        "description" => "A code review prompt",
        "messages" => [
          { "role" => "user", "content" => { "type" => "text", "text" => "Review this code" } },
          { "role" => "assistant", "content" => { "type" => "text", "text" => "Looks good" } }
        ]
      )

      expect(result.description).to eq("A code review prompt")
      expect(result.messages.length).to eq(2)
    end

    it "handles missing messages key" do
      result = described_class.new("description" => "Empty prompt")

      expect(result.messages).to eq([])
    end
  end

  describe Manceps::PromptResult::Message do
    it "has role and text" do
      message = described_class.new(
        "role" => "user",
        "content" => { "type" => "text", "text" => "Hello world" }
      )

      expect(message.role).to eq("user")
      expect(message.text).to eq("Hello world")
      expect(message.content).to be_a(Manceps::Content)
    end

    it "handles missing content" do
      message = described_class.new("role" => "user")

      expect(message.role).to eq("user")
      expect(message.content).to be_nil
      expect(message.text).to be_nil
    end
  end
end
