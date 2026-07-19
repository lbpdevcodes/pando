# frozen_string_literal: true

RSpec.describe Pando::AddContact do
  let(:my_fingerprint) { "aaaa1111" }
  let(:account) { Pando::Crypto::Account.generate }
  let(:device) { Pando::Crypto::Device.generate }
  let(:bundle) { Pando::Crypto::DeviceBundle.issue(device: device, account: account) }
  let(:invite) { Pando::Invite.decode(Pando::Invite.encode(bundle: bundle.to_h, name: "Alice")) }

  def add
    described_class.new(my_fingerprint: my_fingerprint).call(invite)
  end

  it "creates an unverified contact carrying the device bundle" do
    contact, _conversation = add

    expect(contact.trust_level).to eq("unverified")
    expect(contact.display_name).to eq("Alice")
    expect(contact.device_bundle.mailbox).to eq(device.mailbox)
  end

  it "creates a symmetric DM conversation both ends will agree on" do
    _contact, conversation = add

    expect(conversation.kind).to eq("dm")
    expect(conversation.key).to eq(Pando::Protocol::Content.dm_conversation(my_fingerprint, account.fingerprint))
  end

  it "is idempotent — re-adding refreshes rather than duplicates" do
    add
    add

    expect(Pando::Contact.where(fingerprint: account.fingerprint).count).to eq(1)
    expect(Pando::Conversation.count).to eq(1)
  end

  it "preserves an existing verified trust level when re-adding the same device" do
    contact, = add
    contact.update!(trust_level: "verified")

    described_class.new(my_fingerprint: my_fingerprint).call(invite)

    expect(contact.reload.trust_level).to eq("verified")
  end
end
