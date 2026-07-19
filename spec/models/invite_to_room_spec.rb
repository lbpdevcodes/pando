# frozen_string_literal: true

RSpec.describe Pando::InviteToRoom do
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

  let(:alice) { Pando::Crypto::Account.generate }
  let(:alice_device) { Pando::Crypto::Device.generate }
  let(:alice_bundle) { Pando::Crypto::DeviceBundle.issue(device: alice_device, account: alice) }

  let(:bob) { Pando::Crypto::Account.generate }
  let(:bob_device) { Pando::Crypto::Device.generate }
  let(:bob_bundle) { Pando::Crypto::DeviceBundle.issue(device: bob_device, account: bob) }

  let!(:alice_contact) do
    Pando::Contact.create!(fingerprint: alice.fingerprint, name: "Alice",
      bundle: JSON.generate(alice_bundle.to_h))
  end
  let!(:bob_contact) do
    Pando::Contact.create!(fingerprint: bob.fingerprint, name: "Bob",
      bundle: JSON.generate(bob_bundle.to_h))
  end

  let(:room) do
    room = Pando::CreateRoom.new(my_fingerprint: my_account.fingerprint).call(name: "trio")
    room.room_participants.create!(fingerprint: alice.fingerprint)
    room.messages.create!(direction: "incoming", body: "old news", status: "delivered",
      sender_fingerprint: alice.fingerprint, sent_at: Time.now.utc - 60, content_id: "old-1")
    room
  end

  subject(:invite) do
    described_class.new(my_fingerprint: my_account.fingerprint, my_name: "Me", hub: hub)
  end

  def decrypt_all(device)
    hub.sent.filter_map do |frame|
      opened = Pando::Protocol::Envelope.from_h(frame.fetch(:envelope)).open(with: device)
      Pando::Protocol::Content.from_json(opened)
    rescue RbNaCl::CryptoError
      nil
    end
  end

  it "adds the member and broadcasts the snapshot to everyone, history to the invitee" do
    invite.call(room, bob_contact)

    expect(room.room_participants.pluck(:fingerprint))
      .to match_array([my_account.fingerprint, alice.fingerprint, bob.fingerprint])

    alice_contents = decrypt_all(alice_device)
    expect(alice_contents.map(&:kind)).to eq(["room-update"])
    update = alice_contents.first
    expect(update.body["members"].map { |m| m["fp"] })
      .to match_array([my_account.fingerprint, alice.fingerprint, bob.fingerprint])
    expect(update.body["op"]).to eq({"kind" => "add", "fp" => bob.fingerprint})

    bob_contents = decrypt_all(bob_device)
    expect(bob_contents.map(&:kind)).to match_array(%w[room-update room-history])
    history = bob_contents.find { |c| c.kind == "room-history" }
    expect(history.body["messages"].sole["body"]).to eq("old news")
  end

  it "refuses to invite an existing participant" do
    result = invite.call(room, alice_contact)

    expect(result).to be_nil
    expect(hub.sent).to be_empty
  end
end
