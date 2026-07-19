# frozen_string_literal: true

module Pando
  module Attachments
    # Assembler is the receiving half: the manifest creates the incoming
    # attachment Message + Attachment row, chunks land as sealed partials
    # (file-exists = dedup, restart-safe), and once everything is present the
    # pieces concatenate, must reproduce the manifest's BLAKE2b digest exactly,
    # and become the sealed blob. Chunk-before-manifest works because partials
    # persist regardless and finalize re-checks on every ingest.
    class Assembler
      def initialize(blob_store: BlobStore.new)
        @blob_store = blob_store
      end

      def manifest(content, sender_fingerprint:)
        body = content.body
        return nil if Attachment.incoming_exists?(body["attachment_id"])

        message = record_message(content, sender_fingerprint)
        return nil unless message

        attachment = Attachment.create!(message: message,
          attachment_id: body["attachment_id"], name: body["name"], mime: body["mime"],
          size: body["size"].to_i, digest: body["digest"], total_chunks: body["chunks"].to_i,
          status: "receiving", voice: !!body["voice"], duration_s: body["duration_s"])
        try_finalize(attachment)
      end

      def chunk(content)
        body = content.body
        part = body["data"].to_s.unpack1("m0").to_s
        index = body["index"].to_i
        return nil unless part.bytesize.between?(1, CHUNK_BYTES) &&
          index.between?(0, body["total"].to_i - 1)

        blob_store.write_partial(body["attachment_id"], index, part)
        attachment = Attachment.joins(:message)
          .where(attachment_id: body["attachment_id"], messages: {direction: "incoming"}).first
        return nil unless attachment

        attachment.update!(received_chunks: blob_store.partial_count(attachment.attachment_id))
        try_finalize(attachment) || [:attachment, attachment.message.conversation.key]
      end

      private

      attr_reader :blob_store

      def record_message(content, sender_fingerprint)
        conversation = Conversation.find_or_create_by!(key: content.conversation) do |c|
          c.kind = content.conversation.start_with?("room:") ? "room" : "dm"
        end
        message = conversation.messages.create!(direction: "incoming", kind: "attachment",
          body: content.body["name"], status: "delivered",
          sender_fingerprint: sender_fingerprint, content_id: content.id,
          sent_at: parse_time(content.sent_at))
        conversation.touch_activity
        conversation.increment!(:unread_count)
        message
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def try_finalize(attachment)
        return nil unless attachment.status == "receiving"

        parts = blob_store.read_partials(attachment.attachment_id, total: attachment.total_chunks)
        return nil unless parts

        finalize(attachment, parts.join)
      end

      def finalize(attachment, bytes)
        if verified?(attachment, bytes)
          blob_store.write(attachment.attachment_id, bytes)
          attachment.update!(status: "complete", received_chunks: attachment.total_chunks)
          blob_store.purge_partials(attachment.attachment_id)
          [:attachment_complete, attachment.message]
        else
          attachment.update!(status: "failed")
          blob_store.purge_partials(attachment.attachment_id)
          blob_store.delete(attachment.attachment_id)
          [:attachment, attachment.message.conversation.key]
        end
      end

      def verified?(attachment, bytes)
        bytes.bytesize == attachment.size &&
          [RbNaCl::Hash.blake2b(bytes, digest_size: 32)].pack("m0") == attachment.digest
      end

      def parse_time(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        Time.now.utc
      end
    end
  end
end
