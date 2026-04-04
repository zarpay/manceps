require "spec_helper"

RSpec.describe Manceps::Task do
  describe "#initialize" do
    it "initializes from hash data" do
      task = described_class.new(
        "id" => "task-42",
        "status" => "running",
        "result" => { "content" => [{ "type" => "text", "text" => "hello" }] },
        "error" => nil,
        "metadata" => { "progress" => 50 }
      )

      expect(task.id).to eq("task-42")
      expect(task.status).to eq("running")
      expect(task.result).to eq({ "content" => [{ "type" => "text", "text" => "hello" }] })
      expect(task.error).to be_nil
      expect(task.metadata).to eq({ "progress" => 50 })
    end

    it "reads metadata from _meta key when metadata is absent" do
      task = described_class.new(
        "id" => "task-1",
        "status" => "pending",
        "_meta" => { "source" => "test" }
      )

      expect(task.metadata).to eq({ "source" => "test" })
    end

    it "handles missing metadata gracefully" do
      task = described_class.new("id" => "task-1", "status" => "pending")

      expect(task.metadata).to be_nil
    end
  end

  describe "status predicates" do
    it "pending? returns true when status is pending" do
      task = described_class.new("id" => "t", "status" => "pending")
      expect(task.pending?).to be true
      expect(task.running?).to be false
    end

    it "running? returns true when status is running" do
      task = described_class.new("id" => "t", "status" => "running")
      expect(task.running?).to be true
      expect(task.pending?).to be false
    end

    it "completed? returns true when status is completed" do
      task = described_class.new("id" => "t", "status" => "completed")
      expect(task.completed?).to be true
    end

    it "failed? returns true when status is failed" do
      task = described_class.new("id" => "t", "status" => "failed")
      expect(task.failed?).to be true
    end

    it "cancelled? returns true when status is cancelled" do
      task = described_class.new("id" => "t", "status" => "cancelled")
      expect(task.cancelled?).to be true
    end
  end

  describe "#done?" do
    it "returns true for completed" do
      task = described_class.new("id" => "t", "status" => "completed")
      expect(task.done?).to be true
    end

    it "returns true for failed" do
      task = described_class.new("id" => "t", "status" => "failed")
      expect(task.done?).to be true
    end

    it "returns true for cancelled" do
      task = described_class.new("id" => "t", "status" => "cancelled")
      expect(task.done?).to be true
    end

    it "returns false for pending" do
      task = described_class.new("id" => "t", "status" => "pending")
      expect(task.done?).to be false
    end

    it "returns false for running" do
      task = described_class.new("id" => "t", "status" => "running")
      expect(task.done?).to be false
    end
  end

  describe "STATUSES" do
    it "contains all five statuses" do
      expect(described_class::STATUSES).to eq(%w[pending running completed failed cancelled])
    end
  end
end
