# frozen_string_literal: true

RSpec.describe Pando::Client::Outbox do
  let(:sender) { Pando::Crypto::Device.generate }
  let(:account) { Pando::Crypto::Account.generate }
  let(:connection) do
    Class.new do
      attr_reader :sent

      def initialize = @sent = []

      def send_envelope(**frame) = @sent << frame
    end.new
  end
  let(:outbox) { described_class.new(connection: connection, device: sender) }

  def bundle_for(device)
    Pando::Crypto::DeviceBundle.issue(device: device, account: account)
  end

  it "seals and sends one envelope per recipient device" do
    devices = [Pando::Crypto::Device.generate, Pando::Crypto::Device.generate]
    content = Pando::Protocol::Content.text("hi", conversation: "dm:a:b")

    outbox.deliver(content, to_bundles: devices.map { |d| bundle_for(d) })

    expect(connection.sent.map { |f| f.fetch(:to) }).to eq(devices.map(&:mailbox))
    devices.zip(connection.sent) do |device, frame|
      envelope = Pando::Protocol::Envelope.from_h(frame.fetch(:envelope))
      expect(Pando::Protocol::Content.from_json(envelope.open(with: device)).body).to eq("hi")
    end
  end

  it "derives per-device send ids from the content id" do
    device = Pando::Crypto::Device.generate
    content = Pando::Protocol::Content.text("hi", conversation: "dm:a:b")

    outbox.deliver(content, to_bundles: [bundle_for(device)])

    expect(connection.sent.first.fetch(:id)).to eq("#{content.id}/#{device.mailbox}")
  end
end
