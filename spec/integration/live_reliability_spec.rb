# frozen_string_literal: true

require_relative "../support/live_relay_harness"

# Outbound delivery reliability: pending rows composed while offline (or
# stranded by a crash) reach the recipient once Redeliver runs on reconnect,
# and running it again never duplicates anything at the far end.
RSpec.describe "Live outbound delivery reliability", :integration do
  include LiveRelayHarness

  it "delivers offline-composed messages exactly once across repeated redelivery" do
    alice = start_client("Alice")
    bob = start_client("Bob")
    bob_ingestor = ingestor_for(bob)
    add_contact(on: alice, invite: bob.invite_code)
    add_contact(on: bob, invite: alice.invite_code)

    # Composed "while offline": rows exist but nothing was ever enqueued —
    # exactly what a crash before send, or an offline compose, leaves behind.
    conversation = Pando::Conversation.find_by(key: dm_key(alice, bob))
    stranded = conversation.messages.create!(direction: "outgoing", body: "queued in the dark",
      status: "pending", sent_at: Time.now.utc, content_id: SecureRandom.uuid)

    # What Connectivity#apply_status runs on every transition to online.
    Pando::Redeliver.new(hub: alice.hub).call
    Pando::Redeliver.new(hub: alice.hub).call

    wait_until do
      pump(bob, bob_ingestor) { Pando::Message.where(direction: "incoming").exists? }
    end
    copies = Pando::Message.where(direction: "incoming", content_id: stranded.content_id)
    expect(copies.count).to eq(1)
    expect(copies.sole.body).to eq("queued in the dark")

    wait_until { pump(alice, ingestor_for(alice)) { stranded.reload.status == "delivered" } }
  end

  it "delivers a failed message after it is flipped back to pending" do
    alice = start_client("Alice")
    bob = start_client("Bob")
    bob_ingestor = ingestor_for(bob)
    add_contact(on: alice, invite: bob.invite_code)
    add_contact(on: bob, invite: alice.invite_code)

    conversation = Pando::Conversation.find_by(key: dm_key(alice, bob))
    failed = conversation.messages.create!(direction: "outgoing", body: "second try",
      status: "failed", sent_at: Time.now.utc, content_id: SecureRandom.uuid)

    # The "Retry failed messages" command: failed → pending, then redeliver.
    failed.update!(status: "pending")
    Pando::Redeliver.new(hub: alice.hub).call

    wait_until do
      pump(bob, bob_ingestor) do
        Pando::Message.where(direction: "incoming", content_id: failed.content_id).exists?
      end
    end
    wait_until { pump(alice, ingestor_for(alice)) { failed.reload.status == "delivered" } }
  end
end
