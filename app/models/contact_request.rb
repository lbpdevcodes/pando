# frozen_string_literal: true

module Pando
  # ContactRequest is one first-contact handshake with a peer: the incoming copy
  # waits in the inbox until accepted or declined; the outgoing copy tracks a
  # request we sent and flips to accepted when the peer's contact-accept arrives.
  # One row per peer per direction — a re-request updates in place.
  class ContactRequest < ApplicationRecord
    DIRECTIONS = %w[incoming outgoing].freeze
    STATUSES = %w[pending accepted declined].freeze

    attribute :name, :pando_encrypted
    attribute :bundle, :pando_encrypted
    attribute :greeting, :pando_encrypted

    validates :fingerprint, presence: true
    validates :direction, inclusion: {in: DIRECTIONS}
    validates :status, inclusion: {in: STATUSES}

    scope :inbox, -> { where(direction: "incoming", status: "pending").order(:created_at) }

    def display_name
      name.presence || fingerprint
    end

    def device_bundle
      return nil if bundle.blank?

      Crypto::DeviceBundle.from_h(JSON.parse(bundle))
    end
  end
end
