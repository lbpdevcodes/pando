# frozen_string_literal: true

require "json"

module Pando
  # EnrollmentImport materializes the grant blob on a freshly enrolled device:
  # contacts (with their device rosters), conversations (DMs and rooms with
  # membership), and the account's own sibling devices. Every bundle is
  # re-verified — the blob came sealed from a trusted device, but bundles are
  # cheap to check and expensive to trust wrongly.
  class EnrollmentImport
    def initialize(my_fingerprint:)
      @my_fingerprint = my_fingerprint
    end

    def call(blob)
      Array(blob["contacts"]).each { |entry| import_contact(entry) }
      Array(blob["conversations"]).each { |entry| import_conversation(entry) }
      Array(blob["own_devices"]).each { |hash| import_device(hash, expected_fp: my_fingerprint) }
    end

    private

    attr_reader :my_fingerprint

    def import_contact(entry)
      bundles = Array(entry["bundles"]).filter_map do |hash|
        import_device(hash, expected_fp: entry["fp"])
      end
      contact = Contact.find_or_initialize_by(fingerprint: entry["fp"])
      return if contact.persisted?

      contact.update!(name: entry["name"],
        bundle: bundles.first && JSON.generate(bundles.first.to_h))
    end

    def import_device(hash, expected_fp:)
      bundle = Crypto::DeviceBundle.from_h(hash)
      return nil unless bundle.verified? && bundle.fingerprint == expected_fp

      ContactDevice.upsert_bundle(bundle)
      bundle
    rescue KeyError, TypeError
      nil
    end

    def import_conversation(entry)
      conversation = Conversation.find_or_create_by!(key: entry["key"]) do |c|
        c.kind = entry["kind"]
        c.title = entry["title"]
        c.last_activity_at = Time.now.utc
      end
      return unless conversation.room?

      Array(entry["members"]).each do |fingerprint|
        conversation.room_participants.find_or_create_by!(fingerprint: fingerprint)
      end
    end
  end
end
