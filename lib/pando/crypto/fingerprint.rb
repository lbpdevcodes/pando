# frozen_string_literal: true

require "digest"

module Pando
  module Crypto
    # Fingerprint is the short human-comparable identifier for a public key: the first
    # eight bytes of its SHA-256 digest, in lowercase hex. Users read these aloud or
    # compare them on screen to verify a contact out-of-band.
    module Fingerprint
      module_function

      def of(public_key_bytes)
        Digest::SHA256.hexdigest(public_key_bytes)[0, 16]
      end
    end
  end
end
