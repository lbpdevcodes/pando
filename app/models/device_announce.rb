# frozen_string_literal: true

module Pando
  # DeviceAnnounce records a newly enrolled device. The proof is the bundle's
  # own account signature — not the envelope's sender key, which is unknowable
  # for a brand-new device — so we accept announces only for accounts we
  # already know: our own, or an existing contact's. An account can only ever
  # announce its own devices (the fingerprint is derived from the signing key).
  class DeviceAnnounce
    def self.build(bundle, my_fingerprint:)
      Protocol::Content.new(kind: "device-announce",
        conversation: "self:#{my_fingerprint}", body: {"bundle" => bundle.to_h})
    end

    def self.apply(content, my_fingerprint:)
      bundle = verified_bundle(content.body["bundle"])
      return nil unless bundle
      return nil unless known_account?(bundle.fingerprint, my_fingerprint)

      ContactDevice.upsert_bundle(bundle)
      [:device, bundle.fingerprint]
    end

    def self.verified_bundle(hash)
      bundle = Crypto::DeviceBundle.from_h(hash)
      bundle.verified? ? bundle : nil
    rescue KeyError, TypeError
      nil
    end

    def self.known_account?(fingerprint, my_fingerprint)
      fingerprint == my_fingerprint || Contact.exists?(fingerprint: fingerprint)
    end
  end
end
