# frozen_string_literal: true

module Pando
  class OnboardingState < ApplicationState
    # mode: "unlock" (create/open a keyring) or "enroll" (choose a passphrase
    # for this device) or "enroll_waiting" (offer deposited, polling for grant).
    attribute :mode, :string, default: "unlock"
    attribute :error, :string
    attribute :enroll_code, :string
    attribute :safety_code, :string
  end
end
