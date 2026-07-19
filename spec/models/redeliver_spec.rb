# frozen_string_literal: true

RSpec.describe Pando::Redeliver do
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

  def message(status:, body: "hello", content_id: SecureRandom.uuid, conversation: self.conversation)
    conversation.messages.create!(direction: "outgoing", body: body, status: status,
      sent_at: Time.now.utc, content_id: content_id)
  end

  it "re-sends every pending outgoing message with its original content id" do
    pending = message(status: "pending", content_id: "keep-this-id")

    described_class.new(hub: hub).call

    frame = hub.sent.sole
    opened = Pando::Protocol::Envelope.from_h(frame.fetch(:envelope)).open(with: peer_device)
    content = Pando::Protocol::Content.from_json(opened)
    expect(content.id).to eq("keep-this-id")
    expect(content.body).to eq(pending.body)
    expect(content.kind).to eq("text")
  end

  it "leaves sent, delivered, failed, and incoming messages alone" do
    message(status: "sent")
    message(status: "delivered")
    message(status: "failed")
    conversation.messages.create!(direction: "incoming", body: "in", status: "delivered",
      sent_at: Time.now.utc, content_id: "in-1")

    described_class.new(hub: hub).call

    expect(hub.sent).to be_empty
  end

  it "skips conversations whose participants have no resolvable bundles" do
    stranger_dm = Pando::Conversation.create!(key: "dm:aaaa000011112222:bbbb000011112222")
    stranger_dm.messages.create!(direction: "outgoing", body: "void", status: "pending",
      sent_at: Time.now.utc, content_id: "void-1")

    described_class.new(hub: hub).call

    expect(hub.sent).to be_empty
    expect(Pando::Message.find_by(content_id: "void-1").status).to eq("pending")
  end

  it "never re-sends attachment-kind messages as text" do
    conversation.messages.create!(direction: "outgoing", kind: "attachment", body: "photo.png",
      status: "pending", sent_at: Time.now.utc, content_id: "att-msg-1")

    described_class.new(hub: hub).call

    expect(hub.sent).to be_empty
  end

  it "re-sends oldest first so ordering survives a reconnect" do
    message(status: "pending", body: "first", content_id: "a")
      .update!(sent_at: Time.now.utc - 60)
    message(status: "pending", body: "second", content_id: "b")

    described_class.new(hub: hub).call

    ids = hub.sent.map do |frame|
      opened = Pando::Protocol::Envelope.from_h(frame.fetch(:envelope)).open(with: peer_device)
      Pando::Protocol::Content.from_json(opened).id
    end
    expect(ids).to eq(%w[a b])
  end
end
