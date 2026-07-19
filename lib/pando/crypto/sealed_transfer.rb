# frozen_string_literal: true

module Pando
  module Crypto
    # SealedTransfer moves the account seed to a newly enrolling device: sealed
    # anonymously to the device's encryption key, so only that device can open it
    # and the ciphertext reveals nothing about the sender.
    module SealedTransfer
      module_function

      def seal(secret, to:)
        RbNaCl::SealedBox.new(RbNaCl::PublicKey.new(to)).encrypt(secret)
      end

      def open(sealed, with:)
        RbNaCl::SealedBox.from_private_key(with.private_encryption_key).decrypt(sealed)
      end
    end
  end
end
