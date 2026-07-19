# frozen_string_literal: true

RSpec.describe Pando::EnrollmentImport do
  let(:me) { Pando::Crypto::Account.generate }
  let(:sibling_device) { Pando::Crypto::Device.generate }
  let(:sibling_bundle) { Pando::Crypto::DeviceBundle.issue(device: sibling_device, account: me) }

  let(:zoe) { Pando::Crypto::Account.generate }
  let(:zoe_device) { Pando::Crypto::Device.generate }
  let(:zoe_bundle) { Pando::Crypto::DeviceBundle.issue(device: zoe_device, account: zoe) }

  let(:blob) do
    {"contacts" => [{"fp" => zoe.fingerprint, "name" => "Zoe", "bundles" => [zoe_bundle.to_h]}],
     "conversations" => [
       {"key" => "room:abc", "kind" => "room", "title" => "trio",
        "members" => [me.fingerprint, zoe.fingerprint]},
       {"key" => Pando::Protocol::Content.dm_conversation(me.fingerprint, zoe.fingerprint),
        "kind" => "dm", "title" => "Zoe", "members" => []}
     ],
     "own_devices" => [sibling_bundle.to_h]}
  end

  it "materializes contacts, devices, conversations, and own siblings" do
    described_class.new(my_fingerprint: me.fingerprint).call(blob)

    contact = Pando::Contact.find_by(fingerprint: zoe.fingerprint)
    expect(contact.display_name).to eq("Zoe")
    expect(Pando::ContactDevice.bundles_for(zoe.fingerprint).sole.mailbox)
      .to eq(zoe_device.mailbox)
    expect(Pando::ContactDevice.bundles_for(me.fingerprint).sole.mailbox)
      .to eq(sibling_device.mailbox)

    room = Pando::Conversation.find_by(key: "room:abc")
    expect(room.kind).to eq("room")
    expect(room.room_participants.pluck(:fingerprint))
      .to match_array([me.fingerprint, zoe.fingerprint])
    expect(Pando::Conversation.where(kind: "dm").count).to eq(1)
  end

  it "is idempotent and skips bundles that do not verify" do
    tampered = blob.merge(
      "contacts" => [{"fp" => zoe.fingerprint, "name" => "Zoe",
                      "bundles" => [zoe_bundle.to_h.merge("mailbox" => "forged")]}]
    )
    described_class.new(my_fingerprint: me.fingerprint).call(tampered)
    described_class.new(my_fingerprint: me.fingerprint).call(tampered)

    expect(Pando::Contact.where(fingerprint: zoe.fingerprint).count).to eq(1)
    expect(Pando::ContactDevice.where(fingerprint: zoe.fingerprint)).to be_empty
  end
end
