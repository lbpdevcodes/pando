# frozen_string_literal: true

require_relative "../support/live_relay_harness"

# A multi-chunk file crosses the wire between two full clients: manifest +
# chunks fan out through the Outbox, the recipient reassembles and
# digest-verifies, the delivered receipt flips the sender's message, and chunk
# relay receipts drive the sender's attachment to "sent".
RSpec.describe "Live attachment transfer", :integration do
  include LiveRelayHarness

  around do |example|
    Dir.mktmpdir do |dir|
      ENV["PANDO_ROOT"] = dir
      example.run
    ensure
      ENV.delete("PANDO_ROOT")
    end
  end

  it "chunks, reassembles, and digest-verifies a large file end to end" do
    alice = start_client("Alice")
    bob = start_client("Bob")
    alice_ingestor = ingestor_for(alice)
    bob_ingestor = ingestor_for(bob)
    add_contact(on: alice, invite: bob.invite_code)
    add_contact(on: bob, invite: alice.invite_code)

    bytes = SecureRandom.bytes(Pando::Attachments::CHUNK_BYTES * 3 + 999)
    path = File.join(ENV["PANDO_ROOT"], "big.bin")
    File.binwrite(path, bytes)

    conversation = Pando::Conversation.find_by(key: dm_key(alice, bob))
    message = Pando::Attachments::Sender.new(hub: alice.hub)
      .call(path: path, conversation: conversation)
    sent_attachment = message.attachment
    expect(sent_attachment.total_chunks).to eq(4)

    # Bob reassembles; his complete copy is a distinct row (distinct wire id
    # would collide in the shared test DB, so assert via received blob).
    wait_until(timeout: 15) do
      pump(bob, bob_ingestor) do
        Pando::Attachment.exists?(status: "complete", attachment_id: sent_attachment.attachment_id)
      end
    end
    expect(Pando::Attachments::BlobStore.new.read(sent_attachment.attachment_id)).to eq(bytes)
    received = Pando::Attachment.find_by(attachment_id: sent_attachment.attachment_id,
      status: "complete")
    expect(received.received_chunks).to eq(4)

    # Alice's side: chunk relay receipts -> attachment "sent"; Bob's delivered
    # receipt for the manifest -> message "delivered".
    wait_until(timeout: 15) do
      pump(alice, alice_ingestor) do
        sent_attachment.reload.status == "sent" && message.reload.status == "delivered"
      end
    end
  end
end
