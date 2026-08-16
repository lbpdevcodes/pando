# frozen_string_literal: true

require "json"

module Pando
  # ContactExchange handles the two first-contact content kinds on the receiving
  # side: contact-request lands in the inbox, contact-accept closes the loop on a
  # request we sent. Both carry the peer's bundle in the body; a bundle whose
  # encryption key doesn't match the device that sealed the envelope is spoofed
  # and dropped silently. Declines are local-only by design — a requester can't
  # probe whether an account exists or declined.
  class ContactExchange
    def initialize(my_fingerprint:, hub: nil)
      @my_fingerprint = my_fingerprint
      @hub = hub
    end

    def store_request(content, envelope)
      card = verified_card(content, envelope)
      return nil unless card && card.fingerprint != my_fingerprint
      return nil if Contact.exists?(fingerprint: card.fingerprint)
      return nil if ContactRequest.exists?(content_id: content.id, direction: "incoming")

      upsert_incoming(card, content)
    end

    def apply_accept(content, envelope)
      card = verified_card(content, envelope)
      return nil unless card

      request = pending_outgoing(card.fingerprint)
      return nil unless request

      AddContact.new(my_fingerprint: my_fingerprint).call(card)
      request.update!(status: "accepted")
      flush_pending
      [:contact_accepted, card.fingerprint]
    end

    private

    attr_reader :my_fingerprint, :hub

    # Our messages to this peer may be stuck pending from before their bundle
    # was known (a one-sided invite add); the accept completes the contact, so
    # the flush path can finally resolve recipients.
    def flush_pending
      Redeliver.new(hub: hub).call if hub
    end

    def verified_card(content, envelope)
      card = ContactCard.new(name: content.body["name"], bundle: content.body["bundle"])
      bundle = card.verified_bundle
      (bundle && bundle.encryption_public_key == envelope.sender_key) ? card : nil
    end

    def upsert_incoming(card, content)
      request = ContactRequest.find_or_initialize_by(fingerprint: card.fingerprint, direction: "incoming")
      return nil if request.status == "declined"

      request.update!(name: card.name, bundle: JSON.generate(card.bundle),
        greeting: content.body["greeting"], status: "pending", content_id: content.id)
      [:contact_request, card.fingerprint]
    end

    def pending_outgoing(fingerprint)
      ContactRequest.find_by(fingerprint: fingerprint, direction: "outgoing", status: "pending")
    end
  end
end
