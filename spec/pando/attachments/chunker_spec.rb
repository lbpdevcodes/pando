# frozen_string_literal: true

require "securerandom"

RSpec.describe Pando::Attachments::Chunker do
  it "splits bytes into indexed chunks under the chunk size" do
    bytes = SecureRandom.bytes(Pando::Attachments::CHUNK_BYTES + 10)

    chunks = described_class.each_chunk(bytes).to_a

    expect(chunks.length).to eq(2)
    expect(chunks[0][0]).to eq(0)
    expect(chunks[0][1].bytesize).to eq(Pando::Attachments::CHUNK_BYTES)
    expect(chunks[1][1].bytesize).to eq(10)
    expect(chunks.map { |(_, part)| part }.join).to eq(bytes)
  end

  it "counts chunks for exact multiples and empty input" do
    expect(described_class.count(0)).to eq(0)
    expect(described_class.count(1)).to eq(1)
    expect(described_class.count(Pando::Attachments::CHUNK_BYTES)).to eq(1)
    expect(described_class.count(Pando::Attachments::CHUNK_BYTES * 3)).to eq(3)
    expect(described_class.count(Pando::Attachments::CHUNK_BYTES * 3 + 1)).to eq(4)
  end

  it "keeps a max-size chunk's sealed envelope under the relay frame cap" do
    device = Pando::Crypto::Device.generate
    recipient = Pando::Crypto::Device.generate
    chunk = SecureRandom.bytes(Pando::Attachments::CHUNK_BYTES)
    content = Pando::Protocol::Content.new(kind: "attachment-chunk",
      conversation: "room:00000000-0000-0000-0000-000000000000",
      body: {"attachment_id" => SecureRandom.uuid, "index" => 63, "total" => 64,
             "data" => [chunk].pack("m0")})

    envelope = Pando::Protocol::Envelope.seal(content.to_json, from: device,
      to: recipient.encryption_public_key)

    wire_bytes = JSON.generate(envelope.to_h).bytesize
    expect(wire_bytes).to be < Pando::Protocol::Limits.default.max_frame_bytes
    expect(wire_bytes).to be > Pando::Protocol::Limits.default.max_frame_bytes / 2
  end
end
