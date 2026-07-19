# frozen_string_literal: true

module Pando
  module Crypto
    # Identity serializes an account plus this machine's device to and from the
    # JSON-safe hash the keyring seals — the bridge between the crypto objects and
    # at-rest storage.
    module Identity
      module_function

      def generate
        to_h(account: Account.generate, device: Device.generate)
      end

      def to_h(account:, device:)
        {
          "account_seed" => encode(account.seed),
          "device" => {
            "signing_seed" => encode(device.send(:signing_key).to_bytes),
            "encryption_key" => encode(device.private_encryption_key.to_bytes),
            "mailbox" => device.mailbox
          }
        }
      end

      def account_from(hash)
        Account.from_seed(decode(hash.fetch("account_seed")))
      end

      def device_from(hash)
        device = hash.fetch("device")
        Device.new(
          signing_key: RbNaCl::SigningKey.new(decode(device.fetch("signing_seed"))),
          encryption_key: RbNaCl::PrivateKey.new(decode(device.fetch("encryption_key"))),
          mailbox: device.fetch("mailbox")
        )
      end

      def encode(bytes) = [bytes].pack("m0")

      def decode(encoded) = encoded.unpack1("m0")
    end
  end
end
