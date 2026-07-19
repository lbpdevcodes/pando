# frozen_string_literal: true

module Pando
  module Protocol
    # Envelope is the end-to-end encryption unit: a NaCl box from the sender device's
    # encryption key to one recipient device's, opaque to the relay. The box itself
    # authenticates the sender's encryption key; binding that key to an account is the
    # job of the account-signed DeviceBundle, so envelopes carry no extra signature.
    class Envelope
      def self.seal(plaintext, from:, to:)
        box = RbNaCl::Box.new(RbNaCl::PublicKey.new(to), from.private_encryption_key)
        nonce = RbNaCl::Random.random_bytes(box.nonce_bytes)
        new(from: from.mailbox, sender_key: from.encryption_public_key,
          nonce: nonce, ciphertext: box.encrypt(nonce, plaintext))
      end

      def self.from_h(hash)
        new(from: hash.fetch("from"), sender_key: hash.fetch("key").unpack1("m0"),
          nonce: hash.fetch("n").unpack1("m0"), ciphertext: hash.fetch("c").unpack1("m0"))
      end

      attr_reader :from, :sender_key

      def initialize(from:, sender_key:, nonce:, ciphertext:)
        @from = from
        @sender_key = sender_key
        @nonce = nonce
        @ciphertext = ciphertext
      end

      def open(with:)
        RbNaCl::Box.new(RbNaCl::PublicKey.new(sender_key), with.private_encryption_key)
          .decrypt(nonce, ciphertext)
      end

      def to_h
        {"v" => 1, "from" => from, "key" => [sender_key].pack("m0"),
         "n" => [nonce].pack("m0"), "c" => [ciphertext].pack("m0")}
      end

      private

      attr_reader :nonce, :ciphertext
    end
  end
end
