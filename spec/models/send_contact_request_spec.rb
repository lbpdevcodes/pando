# frozen_string_literal: true

RSpec.describe Pando::SendContactRequest do
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

      def bundle = @bundle ||= Pando::Crypto::DeviceBundle.issue(device: @device, account: @account)

      def send_envelope(**frame) = @sent << frame
    end.new(account, device)
  end

  let(:target_account) { Pando::Crypto::Account.generate }
  let(:target_device) { Pando::Crypto::Device.generate }
  let(:target_bundle) { Pando::Crypto::DeviceBundle.issue(device: target_device, account: target_account) }

  subject(:sender) { described_class.new(my_fingerprint: my_account.fingerprint, my_name: "me", hub: hub) }

  it "records an outgoing pending request and delivers it to every verified bundle" do
    sender.call(fingerprint: target_account.fingerprint, bundles: [target_bundle.to_h])

    request = Pando::ContactRequest.sole
    expect(request.direction).to eq("outgoing")
    expect(request.status).to eq("pending")
    expect(request.fingerprint).to eq(target_account.fingerprint)

    frame = hub.sent.sole
    opened = Pando::Protocol::Envelope.from_h(frame.fetch(:envelope)).open(with: target_device)
    content = Pando::Protocol::Content.from_json(opened)
    expect(content.kind).to eq("contact-request")
    expect(content.id).to eq(request.content_id)
    expect(content.body["bundle"]).to eq(hub.bundle.to_h)
  end

  it "skips bundles that do not verify or belong to a different fingerprint" do
    other = Pando::Crypto::DeviceBundle.issue(device: Pando::Crypto::Device.generate,
      account: Pando::Crypto::Account.generate)
    forged = target_bundle.to_h.merge("mailbox" => "tampered")

    result = sender.call(fingerprint: target_account.fingerprint, bundles: [other.to_h, forged])

    expect(result).to be_nil
    expect(hub.sent).to be_empty
    expect(Pando::ContactRequest.count).to eq(0)
  end

  it "re-requests through the same row with a fresh content id" do
    sender.call(fingerprint: target_account.fingerprint, bundles: [target_bundle.to_h])
    first_id = Pando::ContactRequest.sole.content_id
    sender.call(fingerprint: target_account.fingerprint, bundles: [target_bundle.to_h])

    request = Pando::ContactRequest.sole
    expect(request.content_id).not_to eq(first_id)
    expect(hub.sent.length).to eq(2)
  end
end
