# frozen_string_literal: true

require_relative "../support/live_relay_harness"

# The full "never exchanged codes" proof: Bob opts into discoverability, Alice
# finds him by fingerprint alone, sends a contact request, Bob accepts, and the
# two exchange a message — no invite codes anywhere.
RSpec.describe "Live contact request between strangers", :integration do
  include LiveRelayHarness

  it "connects two strangers via fingerprint discovery and request/accept" do
    alice = start_client("Alice")
    bob = start_client("Bob", discoverable: true)
    alice_ingestor = ingestor_for(alice)
    bob_ingestor = ingestor_for(bob)

    # Alice knows only Bob's fingerprint (shared out-of-band).
    bundles = Pando::Client::DirectoryClient.new(relay_url).discover(bob.fingerprint)
    expect(bundles).not_to be_empty

    request = Pando::SendContactRequest.new(my_fingerprint: alice.fingerprint,
      my_name: "Alice", hub: alice.hub).call(fingerprint: bob.fingerprint, bundles: bundles)
    expect(request.status).to eq("pending")

    # Bob's client surfaces the request in his inbox.
    wait_until { pump(bob, bob_ingestor) { Pando::ContactRequest.inbox.exists? } }
    incoming = Pando::ContactRequest.inbox.sole
    expect(incoming.fingerprint).to eq(alice.fingerprint)
    expect(incoming.display_name).to eq("Alice")

    # Bob accepts → contact both ways once Alice ingests the contact-accept.
    Pando::AcceptContactRequest.new(my_fingerprint: bob.fingerprint, my_name: "Bob",
      hub: bob.hub).call(incoming)
    expect(Pando::Contact.find_by(fingerprint: alice.fingerprint)).not_to be_nil

    wait_until { pump(alice, alice_ingestor) { request.reload.status == "accepted" } }
    expect(Pando::Contact.find_by(fingerprint: bob.fingerprint)).not_to be_nil

    # The new contacts carry a real conversation end-to-end.
    conversation = Pando::Conversation.find_by(key: dm_key(alice, bob))
    outgoing = send_text(alice, conversation, "hi bob, found you by fingerprint")
    wait_until do
      pump(bob, bob_ingestor) { Pando::Message.where(direction: "incoming").exists? }
    end
    expect(Pando::Message.where(direction: "incoming").last.body)
      .to eq("hi bob, found you by fingerprint")
    wait_until { pump(alice, alice_ingestor) { outgoing.reload.status == "delivered" } }
  end

  it "keeps an undiscoverable stranger unreachable by fingerprint" do
    charlie = start_client("Charlie")

    bundles = Pando::Client::DirectoryClient.new(relay_url).discover(charlie.fingerprint)

    expect(bundles).to be_empty
  end
end
