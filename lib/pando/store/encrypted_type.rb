# frozen_string_literal: true

require "json"

module Pando
  module Store
    # EncryptedType is an ActiveRecord attribute type that seals a column's value
    # under the profile data key (fresh nonce per write). The database only ever
    # holds SecretEnvelope JSON; reading or writing while the profile is locked
    # raises Store::Locked.
    class EncryptedType < ActiveRecord::Type::Text
      def serialize(value)
        return if value.nil?

        JSON.generate(SecretEnvelope.seal(value.to_s, key: Store.data_key))
      end

      # NaCl hands back BINARY (ASCII-8BIT) plaintext; what went in was UTF-8
      # text, so re-tag it — interpolating a binary string with multibyte
      # characters into UTF-8 view templates raises Encoding::CompatibilityError.
      def deserialize(value)
        return if value.nil?

        SecretEnvelope.open(JSON.parse(value), key: Store.data_key)
          .force_encoding(Encoding::UTF_8)
      end
    end
  end
end
