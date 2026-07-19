# frozen_string_literal: true

RSpec.describe Pando::Protocol::Frames do
  it "round-trips a challenge frame" do
    decoded = described_class.decode(described_class::Challenge.new(nonce: "abc").encode)

    expect(decoded).to eq(described_class::Challenge.new(nonce: "abc"))
  end

  it "round-trips a subscribe frame" do
    frame = described_class::Subscribe.new(mailbox: "m1", device_key: "k", sig: "s")

    expect(described_class.decode(frame.encode)).to eq(frame)
  end

  it "round-trips a send frame with its envelope payload" do
    frame = described_class::Send.new(id: "msg-1", to: "m2", envelope: {"v" => 1, "c" => "x"}, ttl: 3600)
    decoded = described_class.decode(frame.encode)

    expect(decoded.envelope).to eq({"v" => 1, "c" => "x"})
    expect(decoded.ttl).to eq(3600)
  end

  it "round-trips receipt, message, ack and error frames" do
    [
      described_class::Receipt.new(id: "msg-1", status: "queued", expires_at: "2026-07-19T00:00:00Z"),
      described_class::Message.new(seq: 7, to: "m2", envelope: {"c" => "x"}, queued_at: nil),
      described_class::Ack.new(seq: 7),
      described_class::Error.new(code: "queue_full", ref: "msg-1", detail: "mailbox over capacity")
    ].each do |frame|
      expect(described_class.decode(frame.encode)).to eq(frame)
    end
  end

  it "rejects frames with an unknown type" do
    expect { described_class.decode({v: 1, t: "bogus"}.to_json) }
      .to raise_error(described_class::UnknownFrame)
  end

  it "rejects frames with an unsupported version" do
    expect { described_class.decode({v: 99, t: "ack", seq: 1}.to_json) }
      .to raise_error(described_class::UnknownFrame)
  end

  it "rejects unparseable frames" do
    expect { described_class.decode("not json") }.to raise_error(described_class::UnknownFrame)
  end
end
