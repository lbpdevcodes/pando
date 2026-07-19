# frozen_string_literal: true

module Pando
  # CreateRoom starts a room of one: the conversation plus the creator's own
  # participant row. No wire traffic until someone is invited.
  class CreateRoom
    def initialize(my_fingerprint:)
      @my_fingerprint = my_fingerprint
    end

    def call(name:)
      now = Time.now.utc
      room = Conversation.create!(key: Protocol::Content.room_conversation, kind: "room",
        title: name, last_activity_at: now, membership_updated_at: now)
      room.room_participants.create!(fingerprint: @my_fingerprint, joined_at: now)
      room
    end
  end
end
