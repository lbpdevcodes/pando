# frozen_string_literal: true

require "tmpdir"
require "securerandom"

RSpec.describe Pando::Attachments::Assembler do
  around do |example|
    Dir.mktmpdir do |dir|
      ENV["PANDO_ROOT"] = dir
      example.run
    ensure
      ENV.delete("PANDO_ROOT")
    end
  end

  let(:sender_fp) { "aaaa000011112222" }
  let(:conversation) { Pando::Conversation.create!(key: "dm:#{sender_fp}:bbbb000011112222") }
  let(:attachment_id) { SecureRandom.uuid }
  let(:bytes) { SecureRandom.bytes(Pando::Attachments::CHUNK_BYTES + 50) }
  let(:digest) { [RbNaCl::Hash.blake2b(bytes, digest_size: 32)].pack("m0") }
  let(:assembler) { described_class.new }
  let(:store) { Pando::Attachments::BlobStore.new }

  def manifest_content(overrides = {})
    body = {"attachment_id" => attachment_id, "name" => "photo.png", "mime" => "image/png",
            "size" => bytes.bytesize, "digest" => digest, "chunks" => 2,
            "chunk_bytes" => Pando::Attachments::CHUNK_BYTES,
            "voice" => false, "duration_s" => nil}.merge(overrides)
    Pando::Protocol::Content.new(kind: "attachment-manifest", conversation: conversation.key,
      body: body, id: "manifest-#{attachment_id}")
  end

  def chunk_content(index)
    part = bytes.byteslice(index * Pando::Attachments::CHUNK_BYTES, Pando::Attachments::CHUNK_BYTES)
    Pando::Protocol::Content.new(kind: "attachment-chunk", conversation: conversation.key,
      body: {"attachment_id" => attachment_id, "index" => index, "total" => 2,
             "data" => [part].pack("m0")})
  end

  it "assembles in order: manifest, chunks, digest-verified completion" do
    assembler.manifest(manifest_content, sender_fingerprint: sender_fp)
    assembler.chunk(chunk_content(0))
    result = assembler.chunk(chunk_content(1))

    attachment = Pando::Attachment.sole
    expect(attachment.status).to eq("complete")
    expect(store.read(attachment_id)).to eq(bytes)
    expect(store.partial_count(attachment_id)).to eq(0)
    expect(attachment.message.kind).to eq("attachment")
    expect(attachment.message.direction).to eq("incoming")
    expect(result).to eq([:attachment_complete, attachment.message])
  end

  it "tolerates chunks arriving before the manifest" do
    assembler.chunk(chunk_content(1))
    assembler.chunk(chunk_content(0))
    result = assembler.manifest(manifest_content, sender_fingerprint: sender_fp)

    expect(Pando::Attachment.sole.status).to eq("complete")
    expect(store.read(attachment_id)).to eq(bytes)
    expect(result.first).to eq(:attachment_complete)
  end

  it "ignores replayed manifests and duplicate chunks" do
    assembler.manifest(manifest_content, sender_fingerprint: sender_fp)
    assembler.manifest(manifest_content, sender_fingerprint: sender_fp)
    assembler.chunk(chunk_content(0))
    assembler.chunk(chunk_content(0))

    attachment = Pando::Attachment.sole
    expect(attachment.status).to eq("receiving")
    expect(attachment.received_chunks).to eq(1)
    expect(Pando::Message.count).to eq(1)
  end

  it "fails the transfer on a digest mismatch and purges partials" do
    assembler.manifest(manifest_content("digest" => [RbNaCl::Hash.blake2b("wrong",
      digest_size: 32)].pack("m0")), sender_fingerprint: sender_fp)
    assembler.chunk(chunk_content(0))
    assembler.chunk(chunk_content(1))

    attachment = Pando::Attachment.sole
    expect(attachment.status).to eq("failed")
    expect(store.partial_count(attachment_id)).to eq(0)
    expect(File.exist?(store.blob_path(attachment_id))).to be(false)
  end

  it "rejects oversized or out-of-range chunks" do
    assembler.manifest(manifest_content, sender_fingerprint: sender_fp)
    oversized = Pando::Protocol::Content.new(kind: "attachment-chunk",
      conversation: conversation.key,
      body: {"attachment_id" => attachment_id, "index" => 0, "total" => 2,
             "data" => [SecureRandom.bytes(Pando::Attachments::CHUNK_BYTES + 1)].pack("m0")})
    out_of_range = Pando::Protocol::Content.new(kind: "attachment-chunk",
      conversation: conversation.key,
      body: {"attachment_id" => attachment_id, "index" => 9, "total" => 2, "data" => [+"x"].pack("m0")})

    expect(assembler.chunk(oversized)).to be_nil
    expect(assembler.chunk(out_of_range)).to be_nil
    expect(store.partial_count(attachment_id)).to eq(0)
  end
end
