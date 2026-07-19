# frozen_string_literal: true

require_relative "../support/live_relay_harness"

# Per-conversation TTL end to end: a message sent with a timer carries its ttl
# in the content, both ends stamp the same absolute expiry, and the sweep
# purges the rows on both sides.
RSpec.describe "Live message TTL", :integration do
  include LiveRelayHarness

  it "expires a timed message from both ends' history" do
    alice = start_client("Alice")
    bob = start_client("Bob")
    bob_ingestor = ingestor_for(bob)
    add_contact(on: alice, invite: bob.invite_code)
    add_contact(on: bob, invite: alice.invite_code)

    conversation = Pando::Conversation.find_by(key: dm_key(alice, bob))
    conversation.update!(ttl: 1)

    # What ChatController#append_outgoing + transmit do with a timer set.
    now = Time.now.utc
    outgoing = conversation.messages.create!(direction: "outgoing", body: "now you see me",
      status: "pending", sent_at: now, content_id: SecureRandom.uuid,
      expires_at: now + conversation.ttl)
    content = Pando::Protocol::Content.new(kind: "text", conversation: conversation.key,
      body: "now you see me", id: outgoing.content_id, ttl: conversation.ttl,
      sent_at: now.iso8601)
    Pando::Client::Outbox.new(connection: alice.hub, device: alice.hub.device)
      .deliver(content, to_bundles: conversation.contacts.filter_map(&:device_bundle))

    wait_until do
      pump(bob, bob_ingestor) do
        Pando::Message.where(direction: "incoming", content_id: outgoing.content_id).exists?
      end
    end
    incoming = Pando::Message.find_by(direction: "incoming", content_id: outgoing.content_id)
    expect(incoming.expires_at).to be_within(2).of(outgoing.expires_at)

    sleep 1.2
    expect(Pando::Message.unexpired.where(content_id: outgoing.content_id)).to be_empty
    swept = Pando::Message.sweep_expired
    expect(swept).to eq(2)
    expect(Pando::Message.where(content_id: outgoing.content_id)).to be_empty
  end
end
