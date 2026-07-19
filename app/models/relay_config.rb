# frozen_string_literal: true

module Pando
  # RelayConfig is one saved relay (URL + optional access token, encrypted at
  # rest). Exactly one config is active — the one the Hub connects through.
  # Named RelayConfig because Pando::Relay is the relay server itself.
  class RelayConfig < ApplicationRecord
    attribute :token, :pando_encrypted

    validates :url, presence: true, uniqueness: true

    def self.active_relay
      find_by(active: true)
    end

    def activate!
      transaction do
        self.class.where.not(id: id).update_all(active: false)
        update!(active: true)
      end
    end

    def display_name
      name.presence || url
    end
  end
end
