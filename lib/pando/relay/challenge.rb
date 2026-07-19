# frozen_string_literal: true

require "securerandom"

module Pando
  module Relay
    # Challenge is one connection's proof-of-ownership nonce. A subscribe is accepted
    # only when the proof signature verifies under the presented device key AND that
    # key matches the mailbox's published bundle — so possession of a mailbox name is
    # never enough to read its messages.
    class Challenge
      TTL = 30

      attr_reader :nonce

      def initialize(nonce: SecureRandom.hex(16), issued_at: Time.now.to_i)
        @nonce = nonce
        @issued_at = issued_at
      end

      def proof_valid?(mailbox:, device_key:, sig:, directory:)
        published_owner?(mailbox, device_key, directory) &&
          Protocol::SubscribeProof.valid?(sig: sig, device_key: device_key, nonce: nonce, mailbox: mailbox)
      end

      def expired?(now:)
        now > issued_at + TTL
      end

      private

      attr_reader :issued_at

      def published_owner?(mailbox, device_key, directory)
        bundle_hash = directory.bundle_for_mailbox(mailbox)
        return false unless bundle_hash

        RbNaCl::Util.verify32(Crypto::DeviceBundle.from_h(bundle_hash).signing_public_key, device_key)
      end
    end
  end
end
