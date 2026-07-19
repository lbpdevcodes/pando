# frozen_string_literal: true

RSpec.describe Pando::Ingestor do
  let(:hub) do
    Class.new do
      attr_accessor :device
      attr_reader :acked, :sent

      def initialize = (@acked = []) && (@sent = [])

      def ack(seq) = @acked << seq

      def send_envelope(**frame) = @sent << frame
    end.new.tap { |h| h.device = Pando::Crypto::Device.generate }
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
end
