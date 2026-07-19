# frozen_string_literal: true

module Pando
  module Protocol
    # SubscribeProof is the message a device signs to prove mailbox ownership when
    # answering a relay's connection challenge. Client and relay share this module so
    # the signed bytes can never drift apart.
    module SubscribeProof
      PREFIX = "pando-subscribe-v1"

      module_function

      def message(nonce:, mailbox:)
        [PREFIX, nonce, mailbox].join("|")
      end

      def sign(device:, nonce:, mailbox:)
        device.sign(message(nonce: nonce, mailbox: mailbox))
      end

      def valid?(sig:, device_key:, nonce:, mailbox:)
        RbNaCl::VerifyKey.new(device_key).verify(sig, message(nonce: nonce, mailbox: mailbox))
      rescue RbNaCl::BadSignatureError, RbNaCl::LengthError
        false
      end
    end
  end
end
