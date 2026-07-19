# frozen_string_literal: true

require_relative "../support/live_relay_harness"

# Multi-device enrollment over a real relay: a second device joins Alice's
# account through the rendezvous handshake, announces itself, and from then on
# every message to or from Alice reaches every one of her devices. A third
# device is granted BY the second, proving any enrolled device can approve.
#
# Shared-AR-DB caveat: only Bob pumps through an Ingestor; Alice's devices are
# asserted at the decrypted-frame level.
RSpec.describe "Live multi-device enrollment", :integration do
  include LiveRelayHarness

  def rendezvous = Pando::Client::RendezvousClient.new(relay_url)

  def enroll_device(granter_identity:)
    offer = Pando::Client::Enrollment::Offer.new(rendezvous: rendezvous)
    offer.deposit!
    granter = Pando::Client::Enrollment::Grant.new(identity: granter_identity,
      rendezvous: rendezvous)
    pending_offer = granter.fetch_offer(offer.code)
    expect(granter.safety_code(pending_offer)).to eq(offer.safety_code)
    granter.approve!(pending_offer, code: offer.code,
      extra_own_devices: Pando::ContactDevice.bundles_for(
        Pando::Crypto::Identity.account_from(granter_identity).fingerprint
      ).map(&:to_h))
    result = offer.poll
    expect(result).to be_a(Hash)
    result
  end

  def start_hub_for(identity, name)
    hub = Pando::Client::Hub.new(identity: identity, relay_url: relay_url)
    reports = []
    thread = Thread.new { hub.run(build_recorder(reports)) }
    wait_until { reports.any? { |r| r && r["value"] == "online" } }
    client = LiveClient.new(hub: hub, thread: thread, reports: reports,
      fingerprint: Pando::Crypto::Identity.account_from(identity).fingerprint, name: name)
    @clients << client
    client
  end

  def decrypted_texts(client)
    client.reports.dup.filter_map do |report|
      next unless report && report["type"] == "frame"

      frame = report["frame"]
      next unless frame.is_a?(Pando::Protocol::Frames::Message)

      envelope = Pando::Protocol::Envelope.from_h(frame.envelope)
      content = Pando::Protocol::Content.from_json(envelope.open(with: client.hub.device))
      content.body if content.kind == "text"
    rescue RbNaCl::CryptoError
      nil
    end
  end

  it "keeps every device of an account in the loop, and denies cleanly" do
    alice1 = start_client("Alice-1")
    bob = start_client("Bob")
    bob_ingestor = ingestor_for(bob)
    add_contact(on: alice1, invite: bob.invite_code)
    add_contact(on: bob, invite: alice1.invite_code)
    alice_identity = Pando::Crypto::Identity.to_h(account: alice1.hub.account,
      device: alice1.hub.device)
    Pando::ContactDevice.upsert_bundle(alice1.hub.bundle)

    # Device 2 joins through the real rendezvous endpoints.
    result2 = enroll_device(granter_identity: alice_identity)
    expect(Pando::Crypto::Identity.account_from(result2[:identity]).fingerprint)
      .to eq(alice1.fingerprint)
    identity2 = result2[:identity]
    Pando::Crypto::Identity.device_from(identity2).then do |device|
      Pando::ContactDevice.upsert_bundle(
        Pando::Crypto::DeviceBundle.issue(device: device,
          account: Pando::Crypto::Identity.account_from(identity2))
      )
    end

    alice2 = start_hub_for(identity2, "Alice-2")

    # The new device announces itself; Bob's roster gains it.
    announce = Pando::DeviceAnnounce.build(alice2.hub.bundle, my_fingerprint: alice1.fingerprint)
    Pando::Client::Outbox.new(connection: alice2.hub, device: alice2.hub.device)
      .deliver(announce, to_bundles: [Pando::Contact.find_by(fingerprint: bob.fingerprint)
        .device_bundle])
    wait_until do
      pump(bob, bob_ingestor) do
        Pando::ContactDevice.where(fingerprint: alice1.fingerprint).count >= 2
      end
    end

    # Bob's next message fans out to BOTH of Alice's devices.
    conversation = Pando::Conversation.find_by(key: dm_key(alice1, bob))
    content = Pando::Protocol::Content.new(kind: "text", conversation: conversation.key,
      body: "hello every alice")
    Pando::Client::Outbox.new(connection: bob.hub, device: bob.hub.device).deliver(content,
      to_bundles: Pando::RecipientBundles.for(conversation, my_fingerprint: bob.fingerprint,
        my_mailbox: bob.hub.device.mailbox))
    wait_until { decrypted_texts(alice1).include?("hello every alice") }
    wait_until { decrypted_texts(alice2).include?("hello every alice") }

    # Alice device 1 sends: Bob receives it AND device 2 gets the sync copy.
    own_sync = Pando::Protocol::Content.new(kind: "text", conversation: conversation.key,
      body: "sent from device one")
    Pando::Client::Outbox.new(connection: alice1.hub, device: alice1.hub.device).deliver(own_sync,
      to_bundles: Pando::RecipientBundles.for(conversation, my_fingerprint: alice1.fingerprint,
        my_mailbox: alice1.hub.device.mailbox))
    wait_until do
      pump(bob, bob_ingestor) do
        Pando::Message.where(direction: "incoming", content_id: own_sync.id).exists?
      end
    end
    wait_until { decrypted_texts(alice2).include?("sent from device one") }

    # Any enrolled device can grant: device 3 is approved by device 2.
    result3 = enroll_device(granter_identity: identity2)
    expect(Pando::Crypto::Identity.account_from(result3[:identity]).fingerprint)
      .to eq(alice1.fingerprint)
    expect(result3[:import]["own_devices"].length).to be >= 2

    # Deny path: the offer's slot vanishes and polling reports it.
    denied_offer = Pando::Client::Enrollment::Offer.new(rendezvous: rendezvous)
    denied_offer.deposit!
    Pando::Client::Enrollment::Grant.new(identity: alice_identity, rendezvous: rendezvous)
      .deny!(denied_offer.code)
    expect(denied_offer.poll).to eq(:denied)
  end
end
