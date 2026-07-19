# frozen_string_literal: true

RSpec.describe Pando::Ingestor do
  let(:hub) do
    Class.new do
      attr_accessor :device, :account
      attr_reader :acked, :sent

      def initialize = (@acked = []) && (@sent = [])

      def ack(seq) = @acked << seq

      def send_envelope(**frame) = @sent << frame
    end.new.tap do |h|
      h.device = Pando::Crypto::Device.generate
      h.account = Pando::Crypto::Account.generate
    end
  end

  let(:ingestor) { described_class.new(hub: hub) }
  let(:sender_account) { Pando::Crypto::Account.generate }
  let(:sender) { Pando::Crypto::Device.generate }
  let(:conversation_key) { "dm:aaaa:bbbb" }

  def message_frame(content, seq: 3, from: sender)
    envelope = Pando::Protocol::Envelope.seal(content.to_json, from: from, to: hub.device.encryption_public_key)
    Pando::Protocol::Frames::Message.new(seq: seq, to: hub.device.mailbox, envelope: envelope.to_h, queued_at: nil)
  end

  def text_content(body = "hello", id: nil)
    args = {conversation: conversation_key}
    content = Pando::Protocol::Content.text(body, **args)
    id ? Pando::Protocol::Content.new(kind: "text", conversation: conversation_key, body: body, id: id) : content
  end

  it "ingests a text message into a new conversation and acks it" do
    ingestor.ingest_frame(message_frame(text_content("first contact"), seq: 9))

    conversation = Pando::Conversation.find_by(key: conversation_key)
    expect(conversation).not_to be_nil
    message = conversation.messages.sole
    expect(message.body).to eq("first contact")
    expect(message.direction).to eq("incoming")
    expect(hub.acked).to eq([9])
  end

  it "drops replayed content ids without duplicating messages" do
    content = text_content("only once", id: "fixed-id")
    ingestor.ingest_frame(message_frame(content, seq: 1))
    ingestor.ingest_frame(message_frame(content, seq: 2))

    expect(Pando::Message.where(content_id: "fixed-id").count).to eq(1)
    expect(hub.acked).to eq([1, 2])
  end

  it "titles new conversations after a known contact and sends a delivered receipt" do
    bundle = Pando::Crypto::DeviceBundle.issue(device: sender, account: sender_account)
    Pando::Contact.create!(fingerprint: sender_account.fingerprint, name: "Alice",
      bundle: JSON.generate(bundle.to_h))

    ingestor.ingest_frame(message_frame(text_content("hi")))

    expect(Pando::Conversation.find_by(key: conversation_key).display_title).to eq("Alice")
    receipt = hub.sent.sole
    expect(receipt.fetch(:to)).to eq(sender.mailbox)
    opened = Pando::Protocol::Envelope.from_h(receipt.fetch(:envelope)).open(with: sender)
    expect(Pando::Protocol::Content.from_json(opened).kind).to eq("receipt")
  end

  it "marks an outgoing message delivered on an E2E receipt" do
    conversation = Pando::Conversation.create!(key: conversation_key)
    outgoing = conversation.messages.create!(direction: "outgoing", body: "sent thing",
      status: "sent", sent_at: Time.now.utc, content_id: "out-1")

    receipt = Pando::Protocol::Content.new(kind: "receipt", conversation: conversation_key,
      body: {"of" => "out-1", "status" => "delivered"})
    ingestor.ingest_frame(message_frame(receipt))

    expect(outgoing.reload.status).to eq("delivered")
  end

  it "promotes pending to sent on a relay receipt without downgrading delivered" do
    conversation = Pando::Conversation.create!(key: conversation_key)
    pending = conversation.messages.create!(direction: "outgoing", body: "a", status: "pending",
      sent_at: Time.now.utc, content_id: "p-1")
    delivered = conversation.messages.create!(direction: "outgoing", body: "b", status: "delivered",
      sent_at: Time.now.utc, content_id: "d-1")

    ingestor.ingest_frame(Pando::Protocol::Frames::Receipt.new(id: "p-1/mbox", status: "queued", expires_at: nil))
    ingestor.ingest_frame(Pando::Protocol::Frames::Receipt.new(id: "d-1/mbox", status: "delivered", expires_at: nil))

    expect(pending.reload.status).to eq("sent")
    expect(delivered.reload.status).to eq("delivered")
  end

  it "acks and drops envelopes it can never decrypt" do
    other = Pando::Crypto::Device.generate
    envelope = Pando::Protocol::Envelope.seal("not for us", from: sender, to: other.encryption_public_key)
    frame = Pando::Protocol::Frames::Message.new(seq: 4, to: hub.device.mailbox,
      envelope: envelope.to_h, queued_at: nil)

    ingestor.ingest_frame(frame)

    expect(Pando::Message.count).to eq(0)
    expect(hub.acked).to eq([4])
  end

  it "reports typing without persisting anything" do
    typing = Pando::Protocol::Content.new(kind: "typing", conversation: conversation_key, body: {})

    result = ingestor.ingest_frame(message_frame(typing))

    expect(result).to eq([:typing, conversation_key])
    expect(Pando::Message.count).to eq(0)
  end

  describe "relay error frames" do
    let!(:conversation) { Pando::Conversation.create!(key: conversation_key) }
    let!(:outgoing) do
      conversation.messages.create!(direction: "outgoing", body: "big", status: "pending",
        sent_at: Time.now.utc, content_id: "err-1")
    end

    def error_frame(code:, ref: "err-1/mbox")
      Pando::Protocol::Frames::Error.new(code: code, ref: ref, detail: nil)
    end

    it "marks the referenced message failed on queue_full" do
      result = ingestor.ingest_frame(error_frame(code: "queue_full"))

      expect(outgoing.reload.status).to eq("failed")
      expect(result).to eq([:failed, conversation_key])
    end

    it "marks the referenced message failed on frame_too_large" do
      ingestor.ingest_frame(error_frame(code: "frame_too_large"))

      expect(outgoing.reload.status).to eq("failed")
    end

    it "never demotes a message that already reached delivered" do
      outgoing.update!(status: "delivered")

      result = ingestor.ingest_frame(error_frame(code: "queue_full"))

      expect(outgoing.reload.status).to eq("delivered")
      expect(result).to be_nil
    end

    it "ignores connection-scoped errors and unknown refs" do
      expect(ingestor.ingest_frame(error_frame(code: "unauthorized", ref: nil))).to be_nil
      expect(ingestor.ingest_frame(error_frame(code: "queue_full", ref: "nope/mbox"))).to be_nil
      expect(outgoing.reload.status).to eq("pending")
    end
  end

  describe "TOFU key-change detection" do
    let(:peer_account) { Pando::Crypto::Account.generate }
    let(:peer_device) { Pando::Crypto::Device.generate }
    let(:peer_bundle) { Pando::Crypto::DeviceBundle.issue(device: peer_device, account: peer_account) }
    let(:dm_key) do
      Pando::Protocol::Content.dm_conversation(hub.account.fingerprint, peer_account.fingerprint)
    end

    let!(:contact) do
      Pando::Contact.create!(fingerprint: peer_account.fingerprint, name: "Peer",
        bundle: JSON.generate(peer_bundle.to_h))
    end

    def dm_text(from:)
      content = Pando::Protocol::Content.new(kind: "text", conversation: dm_key, body: "hi")
      message_frame(content, from: from)
    end

    it "flags the contact when a DM arrives sealed by an unknown device key" do
      impostor = Pando::Crypto::Device.generate

      result = ingestor.ingest_frame(dm_text(from: impostor))

      expect(result).to eq([:key_changed, dm_key])
      expect(contact.reload.trust_level).to eq("key_changed")
      expect(Pando::Message.count).to eq(1)
    end

    it "leaves trust untouched when the sealing key matches the pinned bundle" do
      result = ingestor.ingest_frame(dm_text(from: peer_device))

      expect(result).to eq([:message, dm_key])
      expect(contact.reload.trust_level).to eq("unverified")
    end
  end

  describe "rooms" do
    let(:sender_bundle) { Pando::Crypto::DeviceBundle.issue(device: sender, account: sender_account) }
    let(:room_key) { "room:11111111-2222-3333-4444-555555555555" }

    def my_entry
      my_bundle = Pando::Crypto::DeviceBundle.issue(device: hub.device, account: hub.account)
      {"fp" => hub.account.fingerprint, "name" => "Me", "bundles" => [my_bundle.to_h]}
    end

    def sender_entry
      {"fp" => sender_account.fingerprint, "name" => "Alice", "bundles" => [sender_bundle.to_h]}
    end

    it "creates a room with membership from a room-create" do
      content = Pando::Protocol::Content.new(kind: "room-create", conversation: room_key,
        body: {"name" => "trio", "members" => [my_entry, sender_entry]})

      result = ingestor.ingest_frame(message_frame(content))

      room = Pando::Conversation.find_by(key: room_key)
      expect(room.kind).to eq("room")
      expect(room.room_participants.count).to eq(2)
      expect(result).to eq([:room, room_key])
    end

    it "applies room-history only from a current participant" do
      create = Pando::Protocol::Content.new(kind: "room-create", conversation: room_key,
        body: {"name" => "trio", "members" => [my_entry, sender_entry]})
      ingestor.ingest_frame(message_frame(create))

      history = Pando::Protocol::Content.new(kind: "room-history", conversation: room_key,
        body: {"messages" => [{"id" => "h-1", "sender" => sender_account.fingerprint,
                               "sent_at" => Time.now.utc.iso8601, "body" => "backfilled", "ttl" => 0}]})
      outsider = Pando::Crypto::Device.generate

      expect(ingestor.ingest_frame(message_frame(history, from: outsider))).to be_nil
      expect(Pando::Message.count).to eq(0)

      ingestor.ingest_frame(message_frame(history, from: sender))
      expect(Pando::Message.sole.body).to eq("backfilled")
    end

    it "creates room-kind conversations for text arriving on a room key" do
      text = Pando::Protocol::Content.new(kind: "text", conversation: room_key, body: "hi room")

      ingestor.ingest_frame(message_frame(text))

      expect(Pando::Conversation.find_by(key: room_key).kind).to eq("room")
    end
  end

  describe "contact requests" do
    let(:sender_bundle) { Pando::Crypto::DeviceBundle.issue(device: sender, account: sender_account) }

    def request_content(bundle: sender_bundle, id: nil)
      args = {kind: "contact-request", conversation: conversation_key,
              body: {"name" => "Zoe", "bundle" => bundle.to_h, "greeting" => nil}}
      args[:id] = id if id
      Pando::Protocol::Content.new(**args)
    end

    def accept_content(bundle: sender_bundle)
      Pando::Protocol::Content.new(kind: "contact-accept", conversation: conversation_key,
        body: {"name" => "Zoe", "bundle" => bundle.to_h})
    end

    it "stores an incoming contact request in the inbox without creating a conversation" do
      result = ingestor.ingest_frame(message_frame(request_content))

      request = Pando::ContactRequest.inbox.sole
      expect(request.fingerprint).to eq(sender_account.fingerprint)
      expect(request.display_name).to eq("Zoe")
      expect(result).to eq([:contact_request, sender_account.fingerprint])
      expect(Pando::Conversation.count).to eq(0)
    end

    it "drops a request whose bundle does not match the sealing device" do
      impostor = Pando::Crypto::Device.generate

      result = ingestor.ingest_frame(message_frame(request_content, from: impostor))

      expect(result).to be_nil
      expect(Pando::ContactRequest.count).to eq(0)
    end

    it "ignores a request from an already-known contact" do
      Pando::Contact.create!(fingerprint: sender_account.fingerprint, name: "Zoe",
        bundle: JSON.generate(sender_bundle.to_h))

      result = ingestor.ingest_frame(message_frame(request_content))

      expect(result).to be_nil
      expect(Pando::ContactRequest.count).to eq(0)
    end

    it "keeps a declined request declined when the peer re-requests" do
      Pando::ContactRequest.create!(fingerprint: sender_account.fingerprint, direction: "incoming",
        status: "declined", bundle: JSON.generate(sender_bundle.to_h), content_id: "old")

      ingestor.ingest_frame(message_frame(request_content))

      expect(Pando::ContactRequest.sole.status).to eq("declined")
    end

    it "drops a replayed request content id" do
      content = request_content(id: "req-once")

      ingestor.ingest_frame(message_frame(content, seq: 1))
      Pando::ContactRequest.sole.update!(status: "declined")
      ingestor.ingest_frame(message_frame(content, seq: 2))

      expect(Pando::ContactRequest.sole.status).to eq("declined")
    end

    it "accepts a contact-accept by creating the contact and closing the outgoing request" do
      Pando::ContactRequest.create!(fingerprint: sender_account.fingerprint, direction: "outgoing",
        status: "pending", bundle: JSON.generate(sender_bundle.to_h), content_id: "out-req")

      result = ingestor.ingest_frame(message_frame(accept_content))

      expect(Pando::ContactRequest.sole.status).to eq("accepted")
      contact = Pando::Contact.find_by(fingerprint: sender_account.fingerprint)
      expect(contact.display_name).to eq("Zoe")
      expect(Pando::Conversation.where(kind: "dm").count).to eq(1)
      expect(result).to eq([:contact_accepted, sender_account.fingerprint])
    end

    it "drops a contact-accept with no matching outgoing request" do
      result = ingestor.ingest_frame(message_frame(accept_content))

      expect(result).to be_nil
      expect(Pando::Contact.count).to eq(0)
    end

    it "drops a spoofed contact-accept" do
      Pando::ContactRequest.create!(fingerprint: sender_account.fingerprint, direction: "outgoing",
        status: "pending", bundle: JSON.generate(sender_bundle.to_h), content_id: "out-req")
      impostor = Pando::Crypto::Device.generate

      result = ingestor.ingest_frame(message_frame(accept_content, from: impostor))

      expect(result).to be_nil
      expect(Pando::ContactRequest.sole.status).to eq("pending")
    end
  end
end
