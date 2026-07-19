# frozen_string_literal: true

module Pando
  class Contact < ApplicationRecord
    attribute :name, :pando_encrypted
    attribute :bundle, :pando_encrypted

    validates :fingerprint, presence: true, uniqueness: true
    validates :trust_level, inclusion: {in: %w[unverified verified key_changed]}

    def self.for_sender_key(sender_key)
      find_each.find do |contact|
        bundle = contact.device_bundle
        bundle && bundle.encryption_public_key == sender_key
      end
    end

    def display_name
      name.presence || fingerprint
    end

    def device_bundle
      return nil if bundle.blank?

      Crypto::DeviceBundle.from_h(JSON.parse(bundle))
    end
  end
end
