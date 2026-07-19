# frozen_string_literal: true

module Pando
  module Crypto
    # Account is a user's root identity: an Ed25519 keypair that signs device bundles
    # and is identified by its fingerprint. The seed is the only secret; every device
    # of the account holds it (transferred via enrollment).
    class Account
      def self.generate
        new(signing_key: RbNaCl::SigningKey.generate)
      end

      def self.from_seed(seed)
        new(signing_key: RbNaCl::SigningKey.new(seed))
      end

      def initialize(signing_key:)
        @signing_key = signing_key
      end

      def seed
        signing_key.to_bytes
      end

      def public_key
        signing_key.verify_key.to_bytes
      end

      def fingerprint
        Fingerprint.of(public_key)
      end

      def sign(message)
        signing_key.sign(message)
      end

      def verify(message, signature)
        signing_key.verify_key.verify(signature, message)
      rescue RbNaCl::BadSignatureError
        false
      end

      private

      attr_reader :signing_key
    end
  end
end
