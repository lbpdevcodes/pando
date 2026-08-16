# frozen_string_literal: true

require "json"

module Pando
  # AcceptContactRequest turns an inbox request into a mutual contact: the local
  # Contact + DM conversation are created immediately, and a contact-accept
  # (carrying our name and bundle) travels back so the requester's side completes
  # too. Accepting while offline still creates the contact — the accept frame is
  # simply not sent, and the requester's request stays pending until we re-accept
  # or they re-request.
  class AcceptContactRequest
    def initialize(my_fingerprint:, my_name:, hub:)
      @my_fingerprint = my_fingerprint
      @my_name = my_name
      @hub = hub
    end

    def call(request)
      card = ContactCard.new(name: request.name, bundle: JSON.parse(request.bundle))
      AddContact.new(my_fingerprint: my_fingerprint).call(card)
      send_accept(request) if hub
      request.update!(status: "accepted")
      flush_pending
      request
    end

    private

    attr_reader :my_fingerprint, :my_name, :hub

    # The requester may have messages stuck pending from before they knew our
    # bundle — or we from before we knew theirs. Now that the contact exists
    # both ways, the flush path can resolve recipients.
    def flush_pending
      Redeliver.new(hub: hub).call if hub
    end

    def send_accept(request)
      content = Protocol::Content.new(kind: "contact-accept",
        conversation: Protocol::Content.dm_conversation(my_fingerprint, request.fingerprint),
        body: {"name" => my_name, "bundle" => hub.bundle.to_h})
      Client::Outbox.new(connection: hub, device: hub.device)
        .deliver(content, to_bundles: [request.device_bundle])
    end
  end
end
