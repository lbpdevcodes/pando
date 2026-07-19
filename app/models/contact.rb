# frozen_string_literal: true

module Pando
  class Contact < ApplicationRecord
    attribute :name, :pando_encrypted
    attribute :bundle, :pando_encrypted

    validates :fingerprint, presence: true, uniqueness: true
    validates :trust_level, inclusion: {in: %w[unverified verified key_changed]}

    # Resolves the sealing device of an inbound envelope to its account. The
    # device roster is the indexed source of truth; the legacy scan over
    # single-bundle contacts covers rows created before multi-device (and
    # seeds the roster as a side effect of bundles_for elsewhere).
    def self.for_sender_key(sender_key)
      fingerprint = ContactDevice.fingerprint_for_box_key(sender_key)
      return find_by(fingerprint: fingerprint) if fingerprint

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
