# frozen_string_literal: true

require_relative "../support/live_relay_harness"

# A voice note is an attachment with voice metadata: prove the flag and the
# audio bytes survive the full wire round trip so the recipient can play it.
RSpec.describe "Live voice note transfer", :integration do
  include LiveRelayHarness

  around do |example|
    Dir.mktmpdir do |dir|
      ENV["PANDO_ROOT"] = dir
      example.run
    ensure
      ENV.delete("PANDO_ROOT")
    end
  end

  it "delivers a playable wav with voice metadata intact" do
    alice = start_client("Alice")
    bob = start_client("Bob")
    bob_ingestor = ingestor_for(bob)
    add_contact(on: alice, invite: bob.invite_code)
    add_contact(on: bob, invite: alice.invite_code)

    wav = "RIFF#{[36].pack("V")}WAVEfmt #{SecureRandom.bytes(600)}"
    path = File.join(ENV["PANDO_ROOT"], "note.wav")
    File.binwrite(path, wav)

    conversation = Pando::Conversation.find_by(key: dm_key(alice, bob))
    message = Pando::Attachments::Sender.new(hub: alice.hub)
      .call(path: path, conversation: conversation, voice: true, duration_s: 7.0)

    sent = message.attachment
    wait_until do
      pump(bob, bob_ingestor) do
        Pando::Attachment.incoming_exists?(sent.attachment_id) &&
          Pando::Attachment.joins(:message)
            .where(attachment_id: sent.attachment_id, messages: {direction: "incoming"})
            .sole.status == "complete"
      end
    end

    received = Pando::Attachment.joins(:message)
      .where(attachment_id: sent.attachment_id, messages: {direction: "incoming"}).sole
    expect(received.voice).to be(true)
    expect(received.duration_s).to eq(7.0)
    expect(received.mime).to eq("audio/wav")

    bytes = Pando::Attachments::BlobStore.new.read(sent.attachment_id)
    expect(bytes[0, 4]).to eq("RIFF")
    expect(bytes).to eq(wav)
  end
end
