# frozen_string_literal: true

require "securerandom"

module Pando
  module Attachments
    # Sender pushes one file into a conversation: local rows (an attachment-kind
    # Message whose content id is the manifest's id, so the normal receipt
    # lifecycle drives its status) plus the sealed blob, then the manifest and
    # every chunk through the same Outbox fan-out as text. Chunk content ids are
    # "att:<attachment_id>:<index>" so relay receipts can drive send progress
    # without per-chunk Message rows.
    class Sender
      TooLarge = Class.new(StandardError)

      def initialize(hub:, blob_store: BlobStore.new)
        @hub = hub
        @blob_store = blob_store
      end

      def call(path:, conversation:, voice: false, duration_s: nil)
        ensure_size!(path)
        bytes = File.binread(path)
        attachment = record(path, bytes, conversation, voice, duration_s)
        blob_store.write(attachment.attachment_id, bytes)
        deliver(attachment, bytes, conversation)
        attachment.message
      end

      private

      attr_reader :hub, :blob_store

      def ensure_size!(path)
        size = File.size(path)
        return if size <= MAX_ATTACHMENT_BYTES

        raise TooLarge, "#{File.basename(path)} is #{size} bytes (max #{MAX_ATTACHMENT_BYTES})"
      end

      def record(path, bytes, conversation, voice, duration_s)
        name = File.basename(path)
        message = conversation.messages.create!(direction: "outgoing", kind: "attachment",
          body: name, status: "pending", sent_at: Time.now.utc, content_id: SecureRandom.uuid)
        conversation.touch_activity
        Attachment.create!(message: message, attachment_id: SecureRandom.uuid, name: name,
          mime: mime_for(name), size: bytes.bytesize, digest: digest(bytes),
          total_chunks: Chunker.count(bytes.bytesize), status: "sending",
          voice: voice, duration_s: duration_s)
      end

      def deliver(attachment, bytes, conversation)
        return unless hub

        bundles = RecipientBundles.for(conversation,
          my_fingerprint: hub.account.fingerprint, my_mailbox: hub.device.mailbox)
        return if bundles.empty?

        outbox = Client::Outbox.new(connection: hub, device: hub.device)
        outbox.deliver(manifest_content(attachment, conversation), to_bundles: bundles)
        Chunker.each_chunk(bytes) do |index, part|
          outbox.deliver(chunk_content(attachment, conversation, index, part), to_bundles: bundles)
        end
      end

      def manifest_content(attachment, conversation)
        Protocol::Content.new(kind: "attachment-manifest", conversation: conversation.key,
          id: attachment.message.content_id,
          body: {"attachment_id" => attachment.attachment_id, "name" => attachment.name,
                 "mime" => attachment.mime, "size" => attachment.size,
                 "digest" => attachment.digest, "chunks" => attachment.total_chunks,
                 "chunk_bytes" => CHUNK_BYTES, "voice" => attachment.voice,
                 "duration_s" => attachment.duration_s})
      end

      def chunk_content(attachment, conversation, index, part)
        Protocol::Content.new(kind: "attachment-chunk", conversation: conversation.key,
          id: "att:#{attachment.attachment_id}:#{index}",
          body: {"attachment_id" => attachment.attachment_id, "index" => index,
                 "total" => attachment.total_chunks, "data" => [part].pack("m0")})
      end

      def digest(bytes)
        [RbNaCl::Hash.blake2b(bytes, digest_size: 32)].pack("m0")
      end

      def mime_for(name)
        case File.extname(name).downcase
        when ".png" then "image/png"
        when ".jpg", ".jpeg" then "image/jpeg"
        when ".gif" then "image/gif"
        when ".wav" then "audio/wav"
        when ".txt", ".md" then "text/plain"
        when ".pdf" then "application/pdf"
        else "application/octet-stream"
        end
      end
    end
  end
end
