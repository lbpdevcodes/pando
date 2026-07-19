# frozen_string_literal: true

RSpec.describe Pando::AcceptContactRequest do
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

  let(:peer_account) { Pando::Crypto::Account.generate }
  let(:peer_device) { Pando::Crypto::Device.generate }
  let(:peer_bundle) { Pando::Crypto::DeviceBundle.issue(device: peer_device, account: peer_account) }

  let(:request) do
    Pando::ContactRequest.create!(fingerprint: peer_account.fingerprint, direction: "incoming",
      name: "Zoe", bundle: JSON.generate(peer_bundle.to_h), status: "pending", content_id: "req-1")
  end

  def accept(with_hub: hub)
    described_class.new(my_fingerprint: my_account.fingerprint, my_name: "me", hub: with_hub).call(request)
  end

  it "creates the contact and conversation and sends a contact-accept back" do
    accept

    expect(request.reload.status).to eq("accepted")
    contact = Pando::Contact.find_by(fingerprint: peer_account.fingerprint)
    expect(contact.display_name).to eq("Zoe")
    expect(Pando::Conversation.where(kind: "dm").count).to eq(1)

    frame = hub.sent.sole
    opened = Pando::Protocol::Envelope.from_h(frame.fetch(:envelope)).open(with: peer_device)
    content = Pando::Protocol::Content.from_json(opened)
    expect(content.kind).to eq("contact-accept")
    expect(content.body["bundle"]).to eq(hub.bundle.to_h)
  end

  it "still creates the contact when offline, without sending the accept" do
    accept(with_hub: nil)

    expect(request.reload.status).to eq("accepted")
    expect(Pando::Contact.find_by(fingerprint: peer_account.fingerprint)).not_to be_nil
  end
end
