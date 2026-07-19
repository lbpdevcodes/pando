# frozen_string_literal: true

RSpec.describe Pando::RoomBackfill do
  let(:me) { Pando::Crypto::Account.generate }
  let(:alice_fp) { "aaaa000011112222" }
  let(:room) do
    Pando::Conversation.create!(key: "room:backfill-test", kind: "room", title: "history")
  end

  def seed_message(body, direction: "incoming", sender: alice_fp, at: Time.now.utc)
    room.messages.create!(direction: direction, body: body, status: "delivered",
      sender_fingerprint: (direction == "incoming") ? sender : nil,
      sent_at: at, content_id: "seed-#{body.tr(" ", "-")}")
  end

  describe ".build" do
    it "carries recent messages oldest-first with sender attribution" do
      seed_message("first", at: Time.now.utc - 120)
      seed_message("mine", direction: "outgoing", at: Time.now.utc - 60)
      seed_message("last", at: Time.now.utc)

      content = described_class.build(room, my_fingerprint: me.fingerprint)

      entries = content.body.fetch("messages")
      expect(entries.map { |e| e["body"] }).to eq(%w[first mine last])
      expect(entries.first["sender"]).to eq(alice_fp)
      expect(entries[1]["sender"]).to eq(me.fingerprint)
      expect(content.kind).to eq("room-history")
    end

    it "trims oldest entries to stay inside the byte budget" do
      12.times { |i| seed_message("bulk #{i} #{"x" * 300}", at: Time.now.utc - (100 - i)) }

      content = described_class.build(room, my_fingerprint: me.fingerprint, byte_budget: 2_000)

      entries = content.body.fetch("messages")
      expect(entries.length).to be < 12
      expect(entries.last["body"]).to include("bulk 11")
      expect(content.to_json.bytesize).to be <= 2_000
    end
  end

  describe ".apply" do
    def history_content(entries)
      Pando::Protocol::Content.new(kind: "room-history", conversation: room.key,
        body: {"messages" => entries})
    end

    it "inserts history rows as delivered incoming messages with original ids" do
      entries = [{"id" => "orig-1", "sender" => alice_fp, "sent_at" => (Time.now.utc - 60).iso8601,
                  "body" => "hello from the past", "ttl" => 0}]

      result = described_class.apply(history_content(entries), conversation: room,
        my_fingerprint: me.fingerprint)

      message = room.messages.sole
      expect(message.content_id).to eq("orig-1")
      expect(message.direction).to eq("incoming")
      expect(message.status).to eq("delivered")
      expect(message.sender_fingerprint).to eq(alice_fp)
      expect(result).to eq([:room, room.key])
    end

    it "dedupes entries already present and skips my own originals" do
      seed_message("already here")
      entries = [
        {"id" => "seed-already-here", "sender" => alice_fp, "sent_at" => Time.now.utc.iso8601,
         "body" => "already here", "ttl" => 0},
        {"id" => "mine-1", "sender" => me.fingerprint, "sent_at" => Time.now.utc.iso8601,
         "body" => "my own line", "ttl" => 0}
      ]

      described_class.apply(history_content(entries), conversation: room,
        my_fingerprint: me.fingerprint)

      expect(room.messages.count).to eq(1)
    end
  end
end
