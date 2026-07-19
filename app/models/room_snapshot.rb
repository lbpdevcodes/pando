# frozen_string_literal: true

require "json"
require "time"

module Pando
  # RoomSnapshot is the membership document carried by room-create and
  # room-update: the room's name plus the FULL member list, each entry with the
  # member's signed bundles so strangers become addressable contacts on receipt.
  # Snapshots apply last-writer-wins by sent_at; the sealing device must belong
  # to a member of the snapshot (and, for a known room, to a current
  # participant), so outsiders can't rewrite membership. A snapshot that drops
  # our own fingerprint is our removal.
  class RoomSnapshot
    def self.build(conversation, my_entry:)
      members = conversation.contacts
        .reject { |contact| contact.fingerprint == my_entry["fp"] }
        .map do |contact|
          {"fp" => contact.fingerprint, "name" => contact.name,
           "bundles" => ContactDevice.bundles_for(contact.fingerprint).map(&:to_h)}
        end
      {"name" => conversation.title, "members" => members + [my_entry]}
    end

    def self.apply(content, sender_key:, my_fingerprint:)
      new(content, sender_key: sender_key, my_fingerprint: my_fingerprint).apply
    end

    def initialize(content, sender_key:, my_fingerprint:)
      @content = content
      @sender_key = sender_key
      @my_fingerprint = my_fingerprint
    end

    def apply
      return nil unless key.start_with?("room:") && sender_fingerprint
      return nil unless authorized? && fresh?
      return removal if conversation && !member_fingerprints.include?(my_fingerprint)
      return nil unless member_fingerprints.include?(my_fingerprint)

      upsert_room
      [:room, key]
    end

    private

    attr_reader :content, :sender_key, :my_fingerprint

    def key = content.conversation

    def conversation
      @conversation ||= Conversation.find_by(key: key)
    end

    # Entries whose bundle signature verifies AND matches the claimed
    # fingerprint; anything else is forged or broken and is dropped whole.
    def valid_members
      @valid_members ||= content.body.fetch("members", []).filter_map do |entry|
        bundles = verified_bundles(entry)
        {"fp" => entry["fp"], "name" => entry["name"], "bundles" => bundles} unless bundles.empty?
      end
    end

    def verified_bundles(entry)
      Array(entry["bundles"]).filter_map do |hash|
        bundle = Crypto::DeviceBundle.from_h(hash)
        bundle if bundle.verified? && bundle.fingerprint == entry["fp"]
      rescue KeyError, TypeError
        nil
      end
    end

    def member_fingerprints
      valid_members.map { |entry| entry["fp"] }
    end

    # The device that sealed the envelope must appear in the snapshot itself.
    def sender_fingerprint
      @sender_fingerprint ||= valid_members.find do |entry|
        entry["bundles"].any? { |b| b.encryption_public_key == sender_key }
      end&.fetch("fp")
    end

    # For an existing room the sender must additionally be a CURRENT participant.
    def authorized?
      return true unless conversation

      conversation.room_participants.exists?(fingerprint: sender_fingerprint)
    end

    def fresh?
      return true unless conversation&.membership_updated_at

      sent_at > conversation.membership_updated_at
    end

    def sent_at
      Time.iso8601(content.sent_at)
    rescue ArgumentError, TypeError
      Time.now.utc
    end

    def removal
      conversation.room_participants.delete_all
      conversation.update!(membership_updated_at: sent_at)
      [:room_removed, key]
    end

    def upsert_room
      room = conversation || Conversation.create!(key: key, kind: "room",
        last_activity_at: Time.now.utc)
      room.title = content.body["name"] if content.body["name"].present?
      room.membership_updated_at = sent_at
      room.save!
      replace_participants(room)
      upsert_contacts
    end

    def replace_participants(room)
      room.room_participants.delete_all
      member_fingerprints.each do |fingerprint|
        room.room_participants.create!(fingerprint: fingerprint, joined_at: Time.now.utc)
      end
    end

    # Strangers in the snapshot become unverified contacts so we can address
    # them; existing contacts keep their pinned bundle, name, and trust — a
    # snapshot must never be able to rewrite established identity.
    def upsert_contacts
      valid_members.each do |entry|
        next if entry["fp"] == my_fingerprint
        next if Contact.exists?(fingerprint: entry["fp"])

        Contact.create!(fingerprint: entry["fp"], name: entry["name"],
          bundle: JSON.generate(entry["bundles"].first.to_h), trust_level: "unverified")
      end
    end
  end
end
