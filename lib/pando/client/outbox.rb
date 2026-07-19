# frozen_string_literal: true

module Pando
  module Client
    # Outbox is the one send path: it takes a content document and fans it out as a
    # sealed envelope to every recipient device, direct message and room alike. The
    # per-device send id ("<content id>/<mailbox>") lets receipts be matched back to
    # both the message and the device they concern.
    class Outbox
      def initialize(connection:, device:)
        @connection = connection
        @device = device
      end

      def deliver(content, to_bundles:)
        to_bundles.map { |bundle| deliver_to(content, bundle) }
      end

      private

      attr_reader :connection, :device

      def deliver_to(content, bundle)
        envelope = Protocol::Envelope.seal(content.to_json, from: device, to: bundle.encryption_public_key)
        id = "#{content.id}/#{bundle.mailbox}"
        connection.send_envelope(id: id, to: bundle.mailbox, envelope: envelope.to_h, ttl: content.ttl)
        id
      end
    end
  end
end
