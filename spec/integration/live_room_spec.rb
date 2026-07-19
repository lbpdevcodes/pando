# frozen_string_literal: true

require_relative "../support/live_relay_harness"

# Three clients hold a coherent room conversation through a real relay: A
# creates and invites B, they chat, then C joins late and rebuilds the whole
# room — membership, title, and history — purely from the wire.
#
# The harness shares one ActiveRecord database between all "clients", so only
# ONE client may materialize state through the Ingestor. A and B are asserted
# at the decrypted-frame level; before C pumps, the locally-written room rows
# are deleted so C's state provably comes from room-update + room-history.
RSpec.describe "Live group room with three clients", :integration do
  include LiveRelayHarness

  def contents_for(client)
    client.reports.dup.filter_map do |report|
      next unless report && report["type"] == "frame"

      frame = report["frame"]
      next unless frame.is_a?(Pando::Protocol::Frames::Message)

      envelope = Pando::Protocol::Envelope.from_h(frame.envelope)
      Pando::Protocol::Content.from_json(envelope.open(with: client.hub.device))
    rescue RbNaCl::CryptoError
      nil
    end
  end

  it "keeps three clients coherent and backfills the late joiner" do
    alice = start_client("Alice")
    bob = start_client("Bob")
    carol = start_client("Carol")
    add_contact(on: alice, invite: bob.invite_code)
    add_contact(on: bob, invite: alice.invite_code)
    add_contact(on: alice, invite: carol.invite_code)

    # Alice creates the room and invites Bob.
    room = Pando::CreateRoom.new(my_fingerprint: alice.fingerprint).call(name: "the trio")
    invite = Pando::InviteToRoom.new(my_fingerprint: alice.fingerprint, my_name: "Alice",
      hub: alice.hub)
    invite.call(room, Pando::Contact.find_by(fingerprint: bob.fingerprint))

    wait_until { contents_for(bob).any? { |c| c.kind == "room-update" } }
    bob_update = contents_for(bob).find { |c| c.kind == "room-update" }
    expect(bob_update.body["members"].map { |m| m["fp"] })
      .to match_array([alice.fingerprint, bob.fingerprint])

    # A short pre-join conversation.
    send_text(alice, room.reload, "welcome bob")
    wait_until { contents_for(bob).any? { |c| c.kind == "text" && c.body == "welcome bob" } }

    # Alice invites Carol; every member sees the membership change.
    invite.call(room, Pando::Contact.find_by(fingerprint: carol.fingerprint))
    wait_until do
      contents_for(bob).any? do |c|
        c.kind == "room-update" && c.body["members"].any? { |m| m["fp"] == carol.fingerprint }
      end
    end

    # A message sent after the join, for Carol to receive live.
    send_text(alice, room.reload, "carol is here")

    # Simulate Carol's empty device: drop the locally-written room state so her
    # rows can only come from what her hub actually received.
    room.reload.destroy!

    carol_ingestor = ingestor_for(carol)
    wait_until do
      pump(carol, carol_ingestor) do
        rebuilt = Pando::Conversation.find_by(kind: "room")
        rebuilt&.messages&.any? { |m| m.body == "carol is here" }
      end
    end

    rebuilt = Pando::Conversation.find_by(kind: "room")
    expect(rebuilt.display_title).to eq("the trio")
    expect(rebuilt.room_participants.pluck(:fingerprint))
      .to match_array([alice.fingerprint, bob.fingerprint, carol.fingerprint])

    bodies = rebuilt.messages.chronological.map(&:body)
    expect(bodies).to include("welcome bob")   # backfilled history
    expect(bodies).to include("carol is here") # live delivery after joining
    backfilled = rebuilt.messages.find { |m| m.body == "welcome bob" }
    expect(backfilled.sender_fingerprint).to eq(alice.fingerprint)
  end
end
