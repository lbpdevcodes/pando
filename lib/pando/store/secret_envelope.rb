# frozen_string_literal: true

module Pando
  module Store
    # SecretEnvelope seals a byte payload under a 32-byte key as a JSON-safe hash
    # (fresh random nonce per seal). It is the one at-rest encryption primitive:
    # the keyring, encrypted database columns, and attachment blobs all use it.
    module SecretEnvelope
      module_function

      def seal(plaintext, key:)
        box = RbNaCl::SecretBox.new(key)
        nonce = RbNaCl::Random.random_bytes(box.nonce_bytes)
        {"nonce" => [nonce].pack("m0"), "ciphertext" => [box.encrypt(nonce, plaintext)].pack("m0")}
      end

      def open(envelope, key:)
        RbNaCl::SecretBox.new(key).decrypt(
          envelope.fetch("nonce").unpack1("m0"),
          envelope.fetch("ciphertext").unpack1("m0")
        )
      end
    end
  end
end
