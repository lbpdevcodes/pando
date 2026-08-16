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
      when Protocol::Frames::Error then apply_send_error(frame)
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
      return dispatch_own_device(content) if own_device?(envelope)

      case content.kind
      when "text" then store_text(content, envelope)
      when "receipt" then apply_e2e_receipt(content)
      when "typing" then [:typing, content.conversation]
      when "contact-request" then contact_exchange.store_request(content, envelope)
      when "contact-accept" then contact_exchange.apply_accept(content, envelope)
      when "room-create", "room-update" then apply_room_snapshot(content, envelope)
      when "room-history" then apply_room_history(content, envelope)
      when "attachment-manifest" then ingest_manifest(content, envelope)
      when "attachment-chunk" then ingest_chunk(content)
      when "device-announce" then DeviceAnnounce.apply(content, my_fingerprint: my_fingerprint)
      end
    end

    # Frames sealed by our own account's OTHER devices are history sync, not
    # conversation: text lands as an already-sent outgoing copy (never
    # receipted — receipt storms between own devices), everything else is
    # dropped. Attachments don't sync across own devices in v1.
    def dispatch_own_device(content)
      case content.kind
      when "text" then store_own_copy(content)
      when "device-announce" then DeviceAnnounce.apply(content, my_fingerprint: my_fingerprint)
      end
    end

    def own_device?(envelope)
      ContactDevice.fingerprint_for_box_key(envelope.sender_key) == my_fingerprint
    end

    def store_own_copy(content)
      conversation = find_or_create_conversation(content.conversation, nil)
      sent_at = parse_time(content.sent_at)
      copy = conversation.messages.create!(
        direction: "outgoing", body: content.body, status: "sent",
        content_id: content.id, sent_at: sent_at, expires_at: expiry_for(content, sent_at)
      )
      conversation.touch_activity
      copy && [:message, conversation.key]
    rescue ActiveRecord::RecordNotUnique
      # This device originated the message — the row already exists.
      nil
    end

    def my_fingerprint
      hub.account.fingerprint
    end

    def contact_exchange
      ContactExchange.new(my_fingerprint: hub.account.fingerprint, hub: hub)
    end

    def apply_room_snapshot(content, envelope)
      RoomSnapshot.apply(content, sender_key: envelope.sender_key,
        my_fingerprint: hub.account.fingerprint)
    end

    # History is accepted only from a current participant of a room we already
    # know — the membership snapshot always travels first, so the inviter is a
    # contact by the time their backfill arrives.
    def apply_room_history(content, envelope)
      conversation = Conversation.find_by(key: content.conversation)
      sender = Contact.for_sender_key(envelope.sender_key)
      return nil unless conversation&.room? && sender &&
        conversation.room_participants.exists?(fingerprint: sender.fingerprint)

      RoomBackfill.apply(content, conversation: conversation,
        my_fingerprint: hub.account.fingerprint)
    end

    def store_text(content, envelope)
      contact = Contact.for_sender_key(envelope.sender_key)
      conversation = find_or_create_conversation(content.conversation, contact)
      return nil unless record_message(conversation, content, contact)

      conversation.touch_activity
      conversation.increment!(:unread_count)
      send_delivered_receipt(content, contact) if contact
      return [:key_changed, conversation.key] if detect_key_change(conversation, contact)

      [:message, conversation.key]
    end

    # A DM sealed by a device key that doesn't match the peer's pinned bundle is
    # the TOFU alarm: flag the contact key_changed (we don't hold the new bundle
    # here, so there's nothing to re-pin) and let the UI raise it loudly.
    def detect_key_change(conversation, contact)
      return false if contact

      peer = peer_contact(conversation)
      return false unless peer && peer.trust_level != "key_changed"

      peer.update!(trust_level: "key_changed")
      true
    end

    def peer_contact(conversation)
      return nil unless conversation.key.start_with?("dm:")

      peer_fp = conversation.key.split(":").drop(1) - [hub.account.fingerprint]
      Contact.find_by(fingerprint: peer_fp.first)
    end

    # Text can land on a room key before its membership snapshot (a race the
    # relay's per-connection ordering makes rare) — create the room shell so the
    # message isn't lost; the snapshot fills in title and members when it lands.
    def find_or_create_conversation(key, contact)
      Conversation.find_or_create_by!(key: key) do |conversation|
        if key.start_with?("room:")
          conversation.kind = "room"
        else
          conversation.title = contact&.display_name
        end
      end
    end

    def record_message(conversation, content, contact)
      sent_at = parse_time(content.sent_at)
      conversation.messages.create!(
        direction: "incoming", body: content.body, status: "delivered",
        sender_fingerprint: contact&.fingerprint, content_id: content.id,
        sent_at: sent_at, expires_at: expiry_for(content, sent_at)
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # Both ends compute the same absolute expiry from sent_at + ttl; skew is
    # bounded by clock skew between peers, which self-destruct tolerates.
    def expiry_for(content, sent_at)
      ttl = content.ttl.to_i
      ttl.positive? ? sent_at + ttl : nil
    end

    # Every device of the sender flips their copy to delivered.
    def send_delivered_receipt(content, contact)
      receipt = Protocol::Content.new(kind: "receipt", conversation: content.conversation,
        body: {"of" => content.id, "status" => "delivered"})
      Client::Outbox.new(connection: hub, device: hub.device)
        .deliver(receipt, to_bundles: ContactDevice.bundles_for(contact.fingerprint))
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
      reference = frame.id.to_s.split("/").first
      return apply_chunk_receipt(reference) if reference.start_with?("att:")

      message = outgoing_message(reference)
      return nil unless message

      message.update!(status: "sent") if message.status == "pending"
      [:receipt, message.conversation.key]
    end

    def ingest_manifest(content, envelope)
      contact = Contact.for_sender_key(envelope.sender_key)
      complete_attachment(Attachments::Assembler.new
        .manifest(content, sender_fingerprint: contact&.fingerprint))
    end

    def ingest_chunk(content)
      complete_attachment(Attachments::Assembler.new.chunk(content))
    end

    # A finished assembly earns the delivered receipt for its MANIFEST content
    # id — the sender's attachment message flips to delivered only once the
    # whole file verified.
    def complete_attachment(result)
      kind, message = result
      return result unless kind == :attachment_complete

      contact = Contact.find_by(fingerprint: message.sender_fingerprint)
      if contact
        receipt = Protocol::Content.new(kind: "receipt", conversation: message.conversation.key,
          body: {"of" => message.content_id, "status" => "delivered"})
        Client::Outbox.new(connection: hub, device: hub.device)
          .deliver(receipt, to_bundles: [contact.device_bundle])
      end
      [:attachment, message.conversation.key]
    end

    # Chunk relay receipts ("att:<attachment_id>:<index>/<mailbox>") drive send
    # progress. Fan-out to several devices receipts each chunk more than once —
    # the count is an approximation capped at total, good enough for a progress
    # label.
    def apply_chunk_receipt(reference)
      attachment = Attachment.outgoing_for(reference.split(":")[1])
      return nil unless attachment

      acked = [attachment.acked_chunks + 1, attachment.total_chunks].min
      attachment.update!(acked_chunks: acked,
        status: (acked == attachment.total_chunks) ? "sent" : attachment.status)
      [:attachment, attachment.message.conversation.key]
    end

    # queue_full and frame_too_large reference the rejected send (ref is the
    # outbox's "<content_id>/<mailbox>" id) — mark that message failed so the UI
    # shows the ✗ and offers retry. unauthorized/bad_frame carry no message but
    # still surface so the user learns the connection itself is unhealthy.
    MESSAGE_ERROR_CODES = %w[queue_full frame_too_large].freeze

    def apply_send_error(frame)
      reference = frame.ref.to_s
      return fail_attachment(frame.code, reference) if reference.start_with?("att:")
      return [:relay_error, frame.code, nil] unless MESSAGE_ERROR_CODES.include?(frame.code)

      message = outgoing_message(reference.split("/").first)
      return nil unless message && message.status != "delivered"

      message.update!(status: "failed")
      [:relay_error, frame.code, message.conversation.key]
    end

    def fail_attachment(code, reference)
      attachment = Attachment.outgoing_for(reference.split(":")[1])
      return nil unless attachment

      attachment.update!(status: "failed")
      attachment.message.update!(status: "failed") unless attachment.message.status == "delivered"
      [:relay_error, code, attachment.message.conversation.key]
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
