# frozen_string_literal: true

module Pando
  # Attachment is one transferred file: wire identity (attachment_id), the
  # manifest facts (name/mime/size/digest), transfer progress on both sides,
  # and a pointer into the sealed BlobStore. The digest is BLAKE2b over the
  # PLAINTEXT file — reassembly must reproduce it exactly or the transfer fails.
  class Attachment < ApplicationRecord
    STATUSES = %w[sending sent receiving complete failed].freeze

    belongs_to :message, optional: true

    attribute :name, :pando_encrypted

    validates :attachment_id, presence: true
    validates :status, inclusion: {in: STATUSES}

    def self.incoming_exists?(attachment_id)
      joins(:message).where(attachment_id: attachment_id,
        messages: {direction: "incoming"}).exists?
    end

    def self.outgoing_for(attachment_id)
      joins(:message).where(attachment_id: attachment_id,
        messages: {direction: "outgoing"}).first
    end

    def image?
      mime.to_s.start_with?("image/")
    end

    def png?
      mime == "image/png"
    end

    def display_size
      return "#{size} B" if size < 1024
      return "#{(size / 1024.0).round(1)} KB" if size < 1024 * 1024

      "#{(size / (1024.0 * 1024)).round(1)} MB"
    end

    def progress_label
      case status
      when "sending" then "[sending #{acked_chunks}/#{total_chunks}]"
      when "receiving" then "[receiving #{received_chunks}/#{total_chunks}]"
      when "failed" then "[failed]"
      else ""
      end
    end
  end
end
