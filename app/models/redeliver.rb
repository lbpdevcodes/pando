# frozen_string_literal: true

module Pando
  # Redeliver is the Ingestor's mirror image on the send side: every outgoing
  # message still pending — composed offline, or stranded in a dead process's
  # in-memory queue — is rebuilt with its ORIGINAL content id and re-enqueued.
  # Exactly-once holds end to end: the recipient dedupes on [content_id,
  # direction], and a late relay receipt is idempotent (pending→sent only).
  # Failed messages are deliberately excluded — the relay actively rejected
  # those, so they retry only on explicit user action.
  class Redeliver
    def initialize(hub:)
      @hub = hub
    end

    def call
      pending_messages.each { |message| resend(message) }
    end

    private

    attr_reader :hub

    def pending_messages
      Message.where(direction: "outgoing", status: "pending").order(:sent_at, :id)
    end

    def resend(message)
      bundles = message.conversation.contacts.filter_map(&:device_bundle)
      return if bundles.empty?

      Client::Outbox.new(connection: hub, device: hub.device)
        .deliver(rebuild_content(message), to_bundles: bundles)
    end

    def rebuild_content(message)
      Protocol::Content.new(kind: "text", conversation: message.conversation.key,
        body: message.body, id: message.content_id,
        sent_at: message.sent_at&.utc&.iso8601 || Time.now.utc.iso8601)
    end
  end
end
