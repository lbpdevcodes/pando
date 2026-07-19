# frozen_string_literal: true

RSpec.describe Pando::RoomSnapshot do
  let(:me) { Pando::Crypto::Account.generate }
  let(:my_device) { Pando::Crypto::Device.generate }
  let(:my_bundle) { Pando::Crypto::DeviceBundle.issue(device: my_device, account: me) }

  let(:alice) { Pando::Crypto::Account.generate }
  let(:alice_device) { Pando::Crypto::Device.generate }
  let(:alice_bundle) { Pando::Crypto::DeviceBundle.issue(device: alice_device, account: alice) }

  let(:bob) { Pando::Crypto::Account.generate }
  let(:bob_device) { Pando::Crypto::Device.generate }
  let(:bob_bundle) { Pando::Crypto::DeviceBundle.issue(device: bob_device, account: bob) }

  let(:room_key) { "room:11111111-2222-3333-4444-555555555555" }

  def entry(account, bundle, name)
    {"fp" => account.fingerprint, "name" => name, "bundles" => [bundle.to_h]}
  end

  def snapshot_content(members:, name: "design", sent_at: Time.now.utc.iso8601, kind: "room-update")
    Pando::Protocol::Content.new(kind: kind, conversation: room_key,
      body: {"name" => name, "members" => members}, sent_at: sent_at)
  end

  def apply(content, sender_key: alice_device.encryption_public_key)
    described_class.apply(content, sender_key: sender_key, my_fingerprint: me.fingerprint)
  end

  it "creates the room, membership, and unknown-member contacts from an invite" do
    members = [entry(me, my_bundle, "Me"), entry(alice, alice_bundle, "Alice"),
      entry(bob, bob_bundle, "Bob")]

    result = apply(snapshot_content(members: members))

    conversation = Pando::Conversation.find_by(key: room_key)
    expect(conversation.kind).to eq("room")
    expect(conversation.display_title).to eq("design")
    expect(conversation.room_participants.pluck(:fingerprint))
      .to match_array([me, alice, bob].map(&:fingerprint))
    expect(Pando::Contact.pluck(:fingerprint))
      .to match_array([alice.fingerprint, bob.fingerprint])
    expect(result).to eq([:room, room_key])
  end

  it "ignores a snapshot for an unknown room that does not include me" do
    apply(snapshot_content(members: [entry(alice, alice_bundle, "Alice")]))

    expect(Pando::Conversation.count).to eq(0)
  end

  it "rejects a snapshot sealed by a non-member of an existing room" do
    apply(snapshot_content(members: [entry(me, my_bundle, "Me"), entry(alice, alice_bundle, "Alice")]))
    intruder = snapshot_content(
      members: [entry(me, my_bundle, "Me"), entry(bob, bob_bundle, "Bob")],
      sent_at: (Time.now.utc + 5).iso8601
    )

    result = apply(intruder, sender_key: bob_device.encryption_public_key)

    expect(result).to be_nil
    expect(Pando::Conversation.find_by(key: room_key).room_participants.pluck(:fingerprint))
      .to match_array([me.fingerprint, alice.fingerprint])
  end

  it "applies snapshots last-writer-wins by sent_at" do
    now = Time.now.utc
    apply(snapshot_content(members: [entry(me, my_bundle, "Me"), entry(alice, alice_bundle, "Alice"),
      entry(bob, bob_bundle, "Bob")], sent_at: now.iso8601))

    stale = snapshot_content(members: [entry(me, my_bundle, "Me"), entry(alice, alice_bundle, "Alice")],
      sent_at: (now - 60).iso8601)
    result = apply(stale)

    expect(result).to be_nil
    expect(Pando::Conversation.find_by(key: room_key).room_participants.count).to eq(3)
  end

  it "clears my membership when a snapshot no longer includes me" do
    apply(snapshot_content(members: [entry(me, my_bundle, "Me"), entry(alice, alice_bundle, "Alice")]))

    removal = snapshot_content(members: [entry(alice, alice_bundle, "Alice")],
      sent_at: (Time.now.utc + 5).iso8601)
    result = apply(removal)

    expect(result).to eq([:room_removed, room_key])
    expect(Pando::Conversation.find_by(key: room_key).room_participants.count).to eq(0)
  end

  it "never clobbers an existing contact's name, bundle, or trust" do
    existing = Pando::Contact.create!(fingerprint: alice.fingerprint, name: "Allie",
      bundle: JSON.generate(alice_bundle.to_h), trust_level: "verified")

    tampered = entry(alice, alice_bundle, "Fake Alice")
    apply(snapshot_content(members: [entry(me, my_bundle, "Me"), tampered]))

    expect(existing.reload.name).to eq("Allie")
    expect(existing.trust_level).to eq("verified")
  end

  it "skips members whose bundles do not verify or do not match their fp" do
    forged = {"fp" => bob.fingerprint, "name" => "Bob", "bundles" => [alice_bundle.to_h]}

    apply(snapshot_content(members: [entry(me, my_bundle, "Me"),
      entry(alice, alice_bundle, "Alice"), forged]))

    conversation = Pando::Conversation.find_by(key: room_key)
    expect(conversation.room_participants.pluck(:fingerprint))
      .to match_array([me.fingerprint, alice.fingerprint])
    expect(Pando::Contact.find_by(fingerprint: bob.fingerprint)).to be_nil
  end
end
