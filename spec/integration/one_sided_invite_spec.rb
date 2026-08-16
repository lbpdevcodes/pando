# frozen_string_literal: true

require_relative "../support/live_relay_harness"

# The reported bug: Bob adds Alice by pasting her invite code, messages flow
# Bob→Alice, but Alice's replies never leave her device — nothing ever tells
# Alice's client about Bob. The fix: the invite add notifies Alice with a
# contact request, and her accept completes the contact both ways over the
# wire. (The flush of messages stuck pending before the accept is unit-tested
# in accept_contact_request_spec and ingestor_spec: this harness shares one
# database between both clients, so per-client pending state cannot be
# represented honestly here.)
RSpec.describe "One-sided invite add", :integration do
  include LiveRelayHarness

  it "notifies the invitee, and the accept completes the contact both ways" do
    alice = start_client("Alice")
    bob = start_client("Bob")
    alice_ingestor = ingestor_for(alice)
    bob_ingestor = ingestor_for(bob)

    # Bob pastes Alice's invite — the TUI's Add contact flow. Only this side.
    Pando::AddContactFromInvite.new(my_fingerprint: bob.fingerprint, my_name: "Bob", hub: bob.hub)
      .call(Pando::Invite.decode(alice.invite_code))

    # Alice learns of Bob over the wire: a contact request lands in her inbox.
    wait_until { pump(alice, alice_ingestor) { Pando::ContactRequest.inbox.exists? } }
    request = Pando::ContactRequest.inbox.sole
    expect(request.fingerprint).to eq(bob.fingerprint)
    expect(request.display_name).to eq("Bob")

    # Alice accepts; the accept travels back and closes Bob's outgoing request.
    Pando::AcceptContactRequest.new(my_fingerprint: alice.fingerprint, my_name: "Alice",
      hub: alice.hub).call(request)
    wait_until do
      pump(bob, bob_ingestor) do
        Pando::ContactRequest.where(direction: "outgoing", status: "accepted").exists?
      end
    end

    # Both directions now deliver through the relay.
    alice_conversation = Pando::Conversation.find_by(key: dm_key(alice, bob))
    before = Pando::Message.where(direction: "incoming").count
    send_text(alice, alice_conversation, "hi bob, got your request")
    wait_until { pump(bob, bob_ingestor) { Pando::Message.where(direction: "incoming").count > before } }

    bob_conversation = Pando::Conversation.find_by(key: dm_key(alice, bob))
    before = Pando::Message.where(direction: "incoming").count
    send_text(bob, bob_conversation, "hi alice, thanks for accepting")
    wait_until { pump(alice, alice_ingestor) { Pando::Message.where(direction: "incoming").count > before } }

    bodies = Pando::Message.where(direction: "incoming").map(&:body)
    expect(bodies).to include("hi bob, got your request", "hi alice, thanks for accepting")
  end
end
