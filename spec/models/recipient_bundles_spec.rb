# frozen_string_literal: true

RSpec.describe Pando::RecipientBundles do
  let(:me) { Pando::Crypto::Account.generate }
  let(:my_device) { Pando::Crypto::Device.generate }
  let(:my_other_device) { Pando::Crypto::Device.generate }

  let(:peer) { Pando::Crypto::Account.generate }
  let(:peer_device_a) { Pando::Crypto::Device.generate }
  let(:peer_device_b) { Pando::Crypto::Device.generate }

  def issue(device, account)
    Pando::Crypto::DeviceBundle.issue(device: device, account: account)
  end

  let!(:contact) do
    Pando::Contact.create!(fingerprint: peer.fingerprint, name: "Peer",
      bundle: JSON.generate(issue(peer_device_a, peer).to_h))
  end

  let(:conversation) do
    key = Pando::Protocol::Content.dm_conversation(me.fingerprint, peer.fingerprint)
    Pando::Conversation.create!(key: key, kind: "dm")
  end

  it "fans out to every device of every participant plus my own other devices" do
    Pando::ContactDevice.upsert_bundle(issue(peer_device_a, peer))
    Pando::ContactDevice.upsert_bundle(issue(peer_device_b, peer))
    Pando::ContactDevice.upsert_bundle(issue(my_device, me))
    Pando::ContactDevice.upsert_bundle(issue(my_other_device, me))

    bundles = described_class.for(conversation, my_fingerprint: me.fingerprint,
      my_mailbox: my_device.mailbox)

    expect(bundles.map(&:mailbox)).to match_array(
      [peer_device_a.mailbox, peer_device_b.mailbox, my_other_device.mailbox]
    )
  end

  it "falls back to the legacy single bundle for un-migrated contacts" do
    bundles = described_class.for(conversation, my_fingerprint: me.fingerprint,
      my_mailbox: my_device.mailbox)

    expect(bundles.map(&:mailbox)).to eq([peer_device_a.mailbox])
  end
end
