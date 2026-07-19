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
      trust = ObserveContactKey.new.call(contact, invite.verified_bundle.account_public_key)
      contact.bundle = JSON.generate(invite.bundle)
      contact.trust_level = trust.level
      contact.save!
      contact
    end

    # The conversation may predate the contact — their first message creates
    # it untitled when they added us first — so adding them also heals the
    # missing title.
    def ensure_conversation(invite, contact)
      key = Protocol::Content.dm_conversation(my_fingerprint, invite.fingerprint)
      conversation = Conversation.find_or_create_by!(key: key) do |c|
        c.kind = "dm"
        c.last_activity_at = Time.now.utc
      end
      conversation.update!(title: contact.display_name) if conversation.title.blank?
      conversation
    end
  end
end
