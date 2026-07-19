# frozen_string_literal: true

require "json"

module Pando
  # ContactDevice is the device roster: one row per known device of any
  # account — contacts' devices AND our own account's other devices (rows under
  # our own fingerprint, which never has a Contact). The box_key column resolves
  # an inbound envelope's sealing key to an account without decrypting anything.
  # Rows created from an enrollment offer have no bundle yet; they resolve
  # senders but are skipped when sealing until the device-announce arrives.
  class ContactDevice < ApplicationRecord
    attribute :bundle, :pando_encrypted

    validates :fingerprint, presence: true
    validates :mailbox, presence: true, uniqueness: true
    validates :box_key, presence: true

    def self.upsert_bundle(device_bundle)
      record = find_or_initialize_by(mailbox: device_bundle.mailbox)
      record.update!(fingerprint: device_bundle.fingerprint,
        box_key: encode_key(device_bundle.encryption_public_key),
        bundle: JSON.generate(device_bundle.to_h))
      record
    end

    def self.fingerprint_for_box_key(raw_key)
      find_by(box_key: encode_key(raw_key))&.fingerprint
    end

    def self.bundles_for(fingerprint)
      seed_from_legacy(fingerprint) if where(fingerprint: fingerprint).none?

      where(fingerprint: fingerprint).where.not(bundle: nil).filter_map(&:device_bundle)
    end

    def self.encode_key(raw_key)
      [raw_key].pack("m0")
    end

    # Contacts added before multi-device carry one bundle on the Contact row;
    # materialize it here on first read. (Runs post-unlock by construction —
    # every caller already decrypts.)
    def self.seed_from_legacy(fingerprint)
      legacy = Contact.find_by(fingerprint: fingerprint)&.device_bundle
      upsert_bundle(legacy) if legacy
    end

    def device_bundle
      return nil if bundle.blank?

      Crypto::DeviceBundle.from_h(JSON.parse(bundle))
    end
  end
end
