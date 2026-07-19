# frozen_string_literal: true

require_relative "../support/live_relay_harness"

# Two full clients (Hub + Ingestor, the same pieces the TUI runs) exchange a live
# DM through a real relay process — the Phase 4 end-to-end proof.
RSpec.describe "Live DM between two clients", :integration do
  include LiveRelayHarness

  it "delivers a typed message and drives its status to delivered" do
    alice = start_client("Alice")
    bob = start_client("Bob")

    # Each side adds the other from an invite code, exactly as the TUI does.
    alice_ingestor = ingestor_for(alice)
    bob_ingestor = ingestor_for(bob)
    add_contact(on: alice, invite: bob.invite_code)
    add_contact(on: bob, invite: alice.invite_code)

    conversation = Pando::Conversation.find_by(key: dm_key(alice, bob))
    send_text(alice, conversation, "hey bob, this is live")

    # Bob's client ingests the inbound frame → an incoming message row.
    wait_until { pump(bob, bob_ingestor) { Pando::Message.where(direction: "incoming").exists? } }
    incoming = Pando::Message.where(direction: "incoming").last
    expect(incoming.body).to eq("hey bob, this is live")

    # Bob's delivered receipt flows back → Alice's outgoing goes delivered.
    outgoing = Pando::Message.where(direction: "outgoing").last
    wait_until { pump(alice, alice_ingestor) { outgoing.reload.status == "delivered" } }
    expect(outgoing.status).to eq("delivered")
  end
end
