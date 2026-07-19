# frozen_string_literal: true

RSpec.describe Pando::Protocol::Content do
  it "builds text content with a fresh id and timestamp" do
    content = described_class.text("hello", conversation: "dm:aa:bb")

    expect(content.kind).to eq("text")
    expect(content.body).to eq("hello")
    expect(content.id).not_to eq(described_class.text("hello", conversation: "dm:aa:bb").id)
    expect(Time.iso8601(content.sent_at)).to be_within(5).of(Time.now.utc)
  end

  it "round-trips through its wire form" do
    content = described_class.new(kind: "receipt", conversation: "dm:aa:bb", body: {"of" => "msg-1", "status" => "delivered"})
    restored = described_class.from_json(content.to_json)

    expect(restored.kind).to eq("receipt")
    expect(restored.body).to eq({"of" => "msg-1", "status" => "delivered"})
    expect(restored.conversation).to eq("dm:aa:bb")
  end

  it "derives the same DM conversation id regardless of fingerprint order" do
    expect(described_class.dm_conversation("bbb", "aaa")).to eq(described_class.dm_conversation("aaa", "bbb"))
    expect(described_class.dm_conversation("aaa", "bbb")).to eq("dm:aaa:bbb")
  end

  it "rejects malformed content documents" do
    expect { described_class.from_json("{}") }.to raise_error(described_class::Malformed)
    expect { described_class.from_json("junk") }.to raise_error(described_class::Malformed)
  end
end
