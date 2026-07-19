# frozen_string_literal: true

module Pando
  # EnrollmentExport is the bootstrap package an approving device sends a new
  # device inside the grant: everyone we can talk to and every conversation,
  # because contacts are local-only and a fresh database can address no one.
  class EnrollmentExport
    def self.build(my_fingerprint:)
      new(my_fingerprint: my_fingerprint).build
    end

    def initialize(my_fingerprint:)
      @my_fingerprint = my_fingerprint
    end

    def build
      {contacts: contacts, conversations: conversations,
       own_devices: ContactDevice.bundles_for(@my_fingerprint).map(&:to_h)}
    end

    private

    def contacts
      Contact.find_each.map do |contact|
        {"fp" => contact.fingerprint, "name" => contact.name,
         "bundles" => ContactDevice.bundles_for(contact.fingerprint).map(&:to_h)}
      end
    end

    def conversations
      Conversation.find_each.map do |conversation|
        {"key" => conversation.key, "kind" => conversation.kind,
         "title" => conversation.title,
         "members" => conversation.room? ? conversation.room_participants.pluck(:fingerprint) : []}
      end
    end
  end
end
