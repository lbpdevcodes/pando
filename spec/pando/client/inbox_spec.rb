# frozen_string_literal: true

RSpec.describe Pando::Client::Inbox do
  let(:sender) { Pando::Crypto::Device.generate }
  let(:recipient) { Pando::Crypto::Device.generate }
  let(:connection) do
    Class.new do
      attr_reader :acked

      def initialize = @acked = []

      def ack(seq) = @acked << seq
    end.new
  end
  let(:inbox) { described_class.new(connection: connection, device: recipient) }

  def message_frame(plaintext = nil, seq: 7)
    plaintext ||= Pando::Protocol::Content.text("hello", conversation: "dm:a:b").to_json
    envelope = Pando::Protocol::Envelope.seal(plaintext, from: sender, to: recipient.encryption_public_key)
    Pando::Protocol::Frames::Message.new(seq: seq, to: recipient.mailbox, envelope: envelope.to_h, queued_at: nil)
  end

  it "opens an incoming message and acknowledges it" do
    received = inbox.receive(message_frame)

    expect(received.content.body).to eq("hello")
    expect(received.from).to eq(sender.mailbox)
    expect(received.sender_key).to eq(sender.encryption_public_key)
    expect(connection.acked).to eq([7])
  end

  it "does not acknowledge messages that fail to decrypt" do
    frame = message_frame
    tampered = Pando::Protocol::Frames::Message.new(
      seq: frame.seq, to: frame.to, queued_at: nil,
      envelope: frame.envelope.merge("c" => ["forged"].pack("m0"))
    )

    expect { inbox.receive(tampered) }.to raise_error(RbNaCl::CryptoError)
    expect(connection.acked).to be_empty
  end
end
