# frozen_string_literal: true

require "json"

module Pando
  module Crypto
    # DeviceBundle is a device's public identity — its keys and mailbox — signed by
    # the owning account so relays and contacts can prove which account a mailbox
    # belongs to. It is what gets published to directories and shared in invites.
    class DeviceBundle
      def self.issue(device:, account:)
        fields = {
          "account" => encode(account.public_key),
          "sign" => encode(device.signing_public_key),
          "box" => encode(device.encryption_public_key),
          "mailbox" => device.mailbox
        }
        new(**fields.transform_keys(&:to_sym), signature: encode(account.sign(canonical(fields))))
      end

      def self.from_h(hash)
        new(
          account: hash.fetch("account"),
          sign: hash.fetch("sign"),
          box: hash.fetch("box"),
          mailbox: hash.fetch("mailbox"),
          signature: hash.fetch("signature")
        )
      end

      def self.encode(bytes)
        [bytes].pack("m0")
      end

      def self.canonical(fields)
        JSON.generate(fields.sort.to_h)
      end

      attr_reader :mailbox

      def initialize(account:, sign:, box:, mailbox:, signature:)
        @account = account
        @sign = sign
        @box = box
        @mailbox = mailbox
        @signature = signature
      end

      def verified?
        verify_key.verify(decode(signature), self.class.canonical(public_fields))
      rescue RbNaCl::BadSignatureError, RbNaCl::LengthError
        false
      end

      def fingerprint
        Fingerprint.of(account_public_key)
      end

      def account_public_key
        decode(account)
      end

      def signing_public_key
        decode(sign)
      end

      def encryption_public_key
        decode(box)
      end

      def to_h
        public_fields.merge("signature" => signature)
      end

      private

      attr_reader :account, :sign, :box, :signature

      def public_fields
        {"account" => account, "sign" => sign, "box" => box, "mailbox" => mailbox}
      end

      def verify_key
        RbNaCl::VerifyKey.new(account_public_key)
      end

      def decode(encoded)
        encoded.unpack1("m0")
      end
    end
  end
end
