# frozen_string_literal: true

module Pando
  module Crypto
    # Trust tracks how much a contact's pinned public key can be believed: unverified
    # (exchanged via invite or directory), verified (fingerprints compared out-of-band),
    # or key_changed (the key no longer matches the pin — surfaced loudly until the user
    # re-verifies, which re-pins the new key). Immutable; every transition returns a new
    # Trust.
    class Trust
      def self.pin(key)
        new(pinned_key: key, observed_key: key, level: :unverified)
      end

      attr_reader :level

      def initialize(pinned_key:, observed_key:, level:)
        @pinned_key = pinned_key
        @observed_key = observed_key
        @level = level
      end

      def verify
        self.class.new(pinned_key: observed_key, observed_key: observed_key, level: :verified)
      end

      def observe(key)
        return self if key == pinned_key

        self.class.new(pinned_key: pinned_key, observed_key: key, level: :key_changed)
      end

      private

      attr_reader :pinned_key, :observed_key
    end
  end
end
