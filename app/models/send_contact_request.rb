# frozen_string_literal: true

require "json"
require "securerandom"

module Pando
  # SendContactRequest starts first contact with a peer we discovered by
  # fingerprint: it records the outgoing request locally (so the peer's eventual
  # contact-accept has something to close) and delivers a contact-request carrying
  # our own name and bundle — that bundle is what lets the peer reply to a
  # stranger. Discovered bundles are re-verified here; discovery output is
  # untrusted input.
  class SendContactRequest
    def initialize(my_fingerprint:, my_name:, hub:)
      @my_fingerprint = my_fingerprint
      @my_name = my_name
      @hub = hub
    end

    def call(fingerprint:, bundles:)
      verified = verified_bundles(fingerprint, bundles)
      return nil if verified.empty?

      request = upsert_request(fingerprint, verified.first)
      deliver(request, fingerprint, verified)
      request
    end

    private

    attr_reader :my_fingerprint, :my_name, :hub

    def verified_bundles(fingerprint, bundles)
      bundles.filter_map do |hash|
        card = ContactCard.new(name: nil, bundle: hash)
        (card.fingerprint == fingerprint) ? card.verified_bundle : nil
      end
    end

    def upsert_request(fingerprint, bundle)
      request = ContactRequest.find_or_initialize_by(fingerprint: fingerprint, direction: "outgoing")
      request.update!(bundle: JSON.generate(bundle.to_h), status: "pending",
        content_id: SecureRandom.uuid)
      request
    end

    def deliver(request, fingerprint, bundles)
      content = Protocol::Content.new(kind: "contact-request",
        conversation: Protocol::Content.dm_conversation(my_fingerprint, fingerprint),
        id: request.content_id,
        body: {"name" => my_name, "bundle" => hub.bundle.to_h, "greeting" => nil})
      Client::Outbox.new(connection: hub, device: hub.device).deliver(content, to_bundles: bundles)
    end
  end
end
