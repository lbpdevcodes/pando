# frozen_string_literal: true

module Pando
  # InviteToRoom adds a contact to a room and tells the world: the full
  # membership snapshot broadcasts to every member (the invitee learns the room
  # exists from the same document), and the invitee alone receives a
  # room-history backfill. Any current member may invite — membership converges
  # last-writer-wins on the snapshot's sent_at.
  class InviteToRoom
    def initialize(my_fingerprint:, my_name:, hub:)
      @my_fingerprint = my_fingerprint
      @my_name = my_name
      @hub = hub
    end

    def call(room, contact)
      return nil if room.room_participants.exists?(fingerprint: contact.fingerprint)

      now = Time.now.utc
      room.room_participants.create!(fingerprint: contact.fingerprint, joined_at: now)
      room.update!(membership_updated_at: now)
      broadcast_update(room, contact, now)
      send_history(room, contact)
      room
    end

    private

    attr_reader :my_fingerprint, :my_name, :hub

    def broadcast_update(room, invitee, now)
      body = RoomSnapshot.build(room, my_entry: my_entry)
        .merge("op" => {"kind" => "add", "fp" => invitee.fingerprint})
      content = Protocol::Content.new(kind: "room-update", conversation: room.key,
        body: body, sent_at: now.iso8601)
      deliver(content, room.contacts.filter_map(&:device_bundle))
    end

    def send_history(room, invitee)
      content = RoomBackfill.build(room, my_fingerprint: my_fingerprint)
      deliver(content, [invitee.device_bundle].compact)
    end

    def my_entry
      {"fp" => my_fingerprint, "name" => my_name, "bundles" => [hub.bundle.to_h]}
    end

    def deliver(content, bundles)
      return if bundles.empty?

      Client::Outbox.new(connection: hub, device: hub.device)
        .deliver(content, to_bundles: bundles)
    end
  end
end
