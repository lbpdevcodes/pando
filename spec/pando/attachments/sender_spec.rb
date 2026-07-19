# frozen_string_literal: true

require "tmpdir"
require "securerandom"

RSpec.describe Pando::Attachments::Sender do
  around do |example|
    Dir.mktmpdir do |dir|
      ENV["PANDO_ROOT"] = dir
      example.run
    ensure
      ENV.delete("PANDO_ROOT")
    end
  end

  let(:my_account) { Pando::Crypto::Account.generate }
  let(:my_device) { Pando::Crypto::Device.generate }
  let(:hub) do
    account = my_account
    device = my_device
    Class.new do
      attr_reader :sent, :account, :device

      def initialize(account, device)
        @sent = []
        @account = account
        @device = device
      end

      def send_envelope(**frame) = @sent << frame
    end.new(account, device)
  end

  let(:peer_account) { Pando::Crypto::Account.generate }
  let(:peer_device) { Pando::Crypto::Device.generate }
  let(:peer_bundle) { Pando::Crypto::DeviceBundle.issue(device: peer_device, account: peer_account) }

  let(:conversation) do
    Pando::Contact.create!(fingerprint: peer_account.fingerprint, name: "Peer",
      bundle: JSON.generate(peer_bundle.to_h))
    key = Pando::Protocol::Content.dm_conversation(my_account.fingerprint, peer_account.fingerprint)
    Pando::Conversation.create!(key: key, kind: "dm")
  end

  def write_fixture(bytes)
    path = File.join(ENV["PANDO_ROOT"], "photo.png")
    File.binwrite(path, bytes)
    path
  end

  def decrypted_contents
    hub.sent.map do |frame|
      opened = Pando::Protocol::Envelope.from_h(frame.fetch(:envelope)).open(with: peer_device)
      Pando::Protocol::Content.from_json(opened)
    end
  end

  it "creates the message + attachment rows and sends manifest then chunks" do
    bytes = SecureRandom.bytes(Pando::Attachments::CHUNK_BYTES + 100)
    message = described_class.new(hub: hub).call(path: write_fixture(bytes),
      conversation: conversation)

    expect(message.kind).to eq("attachment")
    expect(message.status).to eq("pending")
    attachment = message.attachment
    expect(attachment.status).to eq("sending")
    expect(attachment.total_chunks).to eq(2)
    expect(Pando::Attachments::BlobStore.new.read(attachment.attachment_id)).to eq(bytes)

    contents = decrypted_contents
    expect(contents.map(&:kind)).to eq(%w[attachment-manifest attachment-chunk attachment-chunk])
    manifest = contents.first
    expect(manifest.id).to eq(message.content_id)
    expect(manifest.body["name"]).to eq("photo.png")
    expect(manifest.body["chunks"]).to eq(2)
    expect(manifest.body["digest"])
      .to eq([RbNaCl::Hash.blake2b(bytes, digest_size: 32)].pack("m0"))
    chunk = contents[1]
    expect(chunk.id).to eq("att:#{attachment.attachment_id}:0")
    expect(chunk.body["data"].unpack1("m0"))
      .to eq(bytes.byteslice(0, Pando::Attachments::CHUNK_BYTES))
  end

  it "refuses files over the attachment cap" do
    huge = write_fixture("x")
    allow(File).to receive(:size).with(huge).and_return(Pando::Attachments::MAX_ATTACHMENT_BYTES + 1)

    expect { described_class.new(hub: hub).call(path: huge, conversation: conversation) }
      .to raise_error(Pando::Attachments::Sender::TooLarge)
    expect(hub.sent).to be_empty
    expect(Pando::Message.count).to eq(0)
  end
end
