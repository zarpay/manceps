require "spec_helper"

RSpec.describe Manceps::Auth::None do
  describe "#apply" do
    it "does not modify headers" do
      auth = described_class.new
      headers = {"content-type" => "application/json"}

      auth.apply(headers)

      expect(headers).to eq("content-type" => "application/json")
    end
  end
end
