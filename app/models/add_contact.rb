# frozen_string_literal: true

require "json"

module Pando
  # AddContact turns a decoded invite into local state: a pinned Contact (unverified
  # by default — the user verifies fingerprints out-of-band) and the DM conversation
  # for talking to them. Re-adding an existing contact refreshes their bundle and
  # observes any key change through the trust ladder.
  class AddContact
    def initialize(my_fingerprint:)
      @my_fingerprint = my_fingerprint
    end

    def call(invite)
      contact = upsert_contact(invite)
      conversation = ensure_conversation(invite, contact)
      [contact, conversation]
    end

    private

    attr_reader :my_fingerprint

    def upsert_contact(invite)
      contact = Contact.find_or_initialize_by(fingerprint: invite.fingerprint)
      contact.name = invite.name if contact.name.blank?
      contact.bundle = JSON.generate(invite.bundle)
      contact.trust_level = next_trust(contact, invite).level
      contact.save!
      contact
    end

    def next_trust(contact, invite)
      new_key = invite.verified_bundle.account_public_key
      return Crypto::Trust.pin(new_key) if contact.new_record?

      current_trust(contact).observe(new_key)
    end

    def current_trust(contact)
      previous = contact.device_bundle&.account_public_key
      trust = Crypto::Trust.pin(previous || "")
      (contact.trust_level == "verified") ? trust.verify : trust
    end

    def ensure_conversation(invite, contact)
      key = Protocol::Content.dm_conversation(my_fingerprint, invite.fingerprint)
      Conversation.find_or_create_by!(key: key) do |conversation|
        conversation.kind = "dm"
        conversation.title = contact.display_name
        conversation.last_activity_at = Time.now.utc
      end
    end
  end
end
