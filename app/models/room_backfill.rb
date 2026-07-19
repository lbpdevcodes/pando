# frozen_string_literal: true

require "time"

module Pando
  # RoomBackfill hands a new member the room's recent history: one room-history
  # content carrying the last messages oldest-first, trimmed from the front to
  # stay well under the relay frame cap. Entries keep their ORIGINAL content ids
  # so the [content_id, direction] index dedupes replays, and re-insert as
  # delivered incoming rows — history is a copy attested only by the inviter,
  # never re-receipted.
  class RoomBackfill
    LIMIT = 50
    BYTE_BUDGET = 200_000

    def self.build(conversation, my_fingerprint:, byte_budget: BYTE_BUDGET)
      entries = conversation.messages.chronological.last(LIMIT).map do |message|
        {"id" => message.content_id,
         "sender" => message.outgoing? ? my_fingerprint : message.sender_fingerprint,
         "sent_at" => message.sent_at&.utc&.iso8601, "body" => message.body, "ttl" => 0}
      end
      content = nil
      until entries.empty?
        content = history_content(conversation, entries)
        break if content.to_json.bytesize <= byte_budget

        entries.shift
      end
      content || history_content(conversation, [])
    end

    def self.history_content(conversation, entries)
      Protocol::Content.new(kind: "room-history", conversation: conversation.key,
        body: {"messages" => entries})
    end

    def self.apply(content, conversation:, my_fingerprint:)
      content.body.fetch("messages", []).each do |entry|
        next if entry["sender"] == my_fingerprint

        insert(conversation, entry)
      end
      [:room, conversation.key]
    end

    def self.insert(conversation, entry)
      conversation.messages.create!(
        direction: "incoming", body: entry["body"], status: "delivered",
        sender_fingerprint: entry["sender"], content_id: entry["id"],
        sent_at: parse_time(entry["sent_at"])
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def self.parse_time(value)
      Time.iso8601(value.to_s)
    rescue ArgumentError
      Time.now.utc
    end
  end
end
