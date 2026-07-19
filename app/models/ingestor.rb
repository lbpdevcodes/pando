# frozen_string_literal: true

module Pando
  # Ingestor turns inbound relay frames into local state: decrypted text becomes
  # Message rows, receipts advance delivery statuses, typing surfaces to the UI.
  # Every processed frame is acked; envelopes that can never decrypt (static keys —
  # failure is permanent) are acked and dropped rather than left to replay.
  #
  # Returns [:message, key] / [:typing, key] / [:receipt, key] describing what
  # changed, or nil — callers use it to decide what to re-render.
  class Ingestor
    def initialize(hub:)
      @hub = hub
    end

    def ingest_frame(frame)
      case frame
      when Protocol::Frames::Message then ingest_message(frame)
      when Protocol::Frames::Receipt then apply_relay_receipt(frame)
      end
    end

    private

    attr_reader :hub

    def ingest_message(frame)
      envelope = Protocol::Envelope.from_h(frame.envelope)
      content = Protocol::Content.from_json(envelope.open(with: hub.device))
      dispatch(content, envelope)
    rescue RbNaCl::CryptoError, Protocol::Content::Malformed
      nil
    ensure
      hub.ack(frame.seq)
    end

    def dispatch(content, envelope)
      case content.kind
      when "text" then store_text(content, envelope)
      when "receipt" then apply_e2e_receipt(content)
      when "typing" then [:typing, content.conversation]
      when "contact-request" then contact_exchange.store_request(content, envelope)
      when "contact-accept" then contact_exchange.apply_accept(content, envelope)
      end
    end

    def contact_exchange
      ContactExchange.new(my_fingerprint: hub.account.fingerprint)
    end

    def store_text(content, envelope)
      contact = Contact.for_sender_key(envelope.sender_key)
      conversation = find_or_create_conversation(content.conversation, contact)
      return nil unless record_message(conversation, content, contact)

      conversation.touch_activity
      send_delivered_receipt(content, contact) if contact
      [:message, conversation.key]
    end

    def find_or_create_conversation(key, contact)
      Conversation.find_or_create_by!(key: key) do |conversation|
        conversation.title = contact&.display_name
      end
    end

    def record_message(conversation, content, contact)
      conversation.messages.create!(
        direction: "incoming", body: content.body, status: "delivered",
        sender_fingerprint: contact&.fingerprint, content_id: content.id,
        sent_at: parse_time(content.sent_at)
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def send_delivered_receipt(content, contact)
      receipt = Protocol::Content.new(kind: "receipt", conversation: content.conversation,
        body: {"of" => content.id, "status" => "delivered"})
      Client::Outbox.new(connection: hub, device: hub.device)
        .deliver(receipt, to_bundles: [contact.device_bundle])
    end

    def apply_e2e_receipt(content)
      message = outgoing_message(content.body["of"])
      return nil unless message

      message.update!(status: "delivered") if content.body["status"] == "delivered"
      [:receipt, message.conversation.key]
    end

    # The relay's receipt means "accepted" (forwarded or queued) — promote pending
    # to sent, but never walk back an end-to-end delivered.
    def apply_relay_receipt(frame)
      message = outgoing_message(frame.id.to_s.split("/").first)
      return nil unless message

      message.update!(status: "sent") if message.status == "pending"
      [:receipt, message.conversation.key]
    end

    # Receipts always concern our outgoing copy — the peer's incoming copy shares
    # the content id but must never absorb a delivery status.
    def outgoing_message(content_id)
      Message.find_by(content_id: content_id, direction: "outgoing")
    end

    def parse_time(value)
      Time.iso8601(value)
    rescue ArgumentError, TypeError
      Time.now.utc
    end
  end
end
