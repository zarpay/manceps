require "spec_helper"

RSpec.describe Manceps::Session do
  subject(:session) { described_class.new }

  it "starts inactive with nil id" do
    expect(session.id).to be_nil
    expect(session).not_to be_active
  end

  describe "#next_id" do
    it "increments monotonically" do
      expect(session.next_id).to eq(1)
      expect(session.next_id).to eq(2)
      expect(session.next_id).to eq(3)
    end
  end

  describe "#establish" do
    it "extracts session data from response" do
      response = {
        sessionId: "sess-abc",
        result: {
          capabilities: {tools: {}},
          protocolVersion: "2025-03-26",
          serverInfo: {name: "TestServer", version: "1.0"}
        }
      }

      session.establish(response)

      expect(session.id).to eq("sess-abc")
      expect(session.capabilities).to eq(tools: {})
      expect(session.protocol_version).to eq("2025-03-26")
      expect(session.server_info).to eq(name: "TestServer", version: "1.0")
    end

    it "is active after establish" do
      session.establish(sessionId: "s1", result: {})

      expect(session).to be_active
    end
  end

  describe "#reset" do
    it "clears all state" do
      session.establish(sessionId: "s1", result: {capabilities: {tools: {}}})
      session.next_id

      session.reset

      expect(session.id).to be_nil
      expect(session.capabilities).to eq({})
      expect(session.protocol_version).to be_nil
      expect(session.server_info).to be_nil
      expect(session).not_to be_active
      expect(session.next_id).to eq(1)
    end
  end
end
