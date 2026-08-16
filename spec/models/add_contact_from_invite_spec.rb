# frozen_string_literal: true

RSpec.describe Pando::AddContactFromInvite do
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

  let(:their_account) { Pando::Crypto::Account.generate }
  let(:their_device) { Pando::Crypto::Device.generate }
  let(:their_bundle) { Pando::Crypto::DeviceBundle.issue(device: their_device, account: their_account) }
  let(:invite) { Pando::Invite.decode(Pando::Invite.encode(bundle: their_bundle.to_h, name: "Zoe")) }

  subject(:adder) { described_class.new(my_fingerprint: my_account.fingerprint, my_name: "me", hub: hub) }

  it "creates the contact and delivers a contact-request carrying my name and bundle" do
    adder.call(invite)

    contact = Pando::Contact.find_by(fingerprint: their_account.fingerprint)
    expect(contact.display_name).to eq("Zoe")
    expect(Pando::Conversation.where(kind: "dm").count).to eq(1)

    request = Pando::ContactRequest.sole
    expect(request.direction).to eq("outgoing")
    expect(request.status).to eq("pending")

    frame = hub.sent.sole
    opened = Pando::Protocol::Envelope.from_h(frame.fetch(:envelope)).open(with: their_device)
    content = Pando::Protocol::Content.from_json(opened)
    expect(content.kind).to eq("contact-request")
    expect(content.body["bundle"]).to eq(hub.bundle.to_h)
  end

  it "does not resend the request when the contact is already known" do
    adder.call(invite)
    expect { adder.call(invite) }.not_to change { hub.sent.length }
    expect(Pando::ContactRequest.where(direction: "outgoing", status: "pending").count).to eq(1)
  end

  it "creates the contact without sending anything when there is no connection" do
    described_class.new(my_fingerprint: my_account.fingerprint, my_name: "me", hub: nil).call(invite)

    expect(Pando::Contact.find_by(fingerprint: their_account.fingerprint)).not_to be_nil
    expect(Pando::ContactRequest.count).to eq(0)
    expect(hub.sent).to be_empty
  end
end
