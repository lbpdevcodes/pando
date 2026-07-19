# frozen_string_literal: true

module Pando
  # ObserveContactKey runs the TOFU trust ladder for one observation: seeing a
  # contact's account key again. A brand-new contact pins the key as unverified;
  # a matching key keeps the current level; a different key drops to key_changed
  # — held there until the user explicitly re-verifies.
  class ObserveContactKey
    def call(contact, new_key)
      return Crypto::Trust.pin(new_key) if contact.new_record?

      current_trust(contact).observe(new_key)
    end

    private

    def current_trust(contact)
      previous = contact.device_bundle&.account_public_key
      trust = Crypto::Trust.pin(previous || "")
      (contact.trust_level == "verified") ? trust.verify : trust
    end
  end
end
