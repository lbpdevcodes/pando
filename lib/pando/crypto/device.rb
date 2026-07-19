# frozen_string_literal: true

require "securerandom"

module Pando
  module Crypto
    # Device is one enrolled machine of an account: an Ed25519 signing pair (proves
    # mailbox ownership to relays), a Curve25519 encryption pair (receives sealed
    # messages), and the random mailbox address other devices send to.
    class Device
      def self.generate
        new(
          signing_key: RbNaCl::SigningKey.generate,
          encryption_key: RbNaCl::PrivateKey.generate,
          mailbox: SecureRandom.hex(16)
        )
      end

      attr_reader :mailbox

      def initialize(signing_key:, encryption_key:, mailbox:)
        @signing_key = signing_key
        @encryption_key = encryption_key
        @mailbox = mailbox
      end

      def signing_public_key
        signing_key.verify_key.to_bytes
      end

      def encryption_public_key
        encryption_key.public_key.to_bytes
      end

      def sign(message)
        signing_key.sign(message)
      end

      def private_encryption_key
        encryption_key
      end

      private

      attr_reader :signing_key, :encryption_key
    end
  end
end
