# frozen_string_literal: true

module Pando
  class Contact < ApplicationRecord
    attribute :name, :pando_encrypted

    validates :fingerprint, presence: true, uniqueness: true
    validates :trust_level, inclusion: {in: %w[unverified verified key_changed]}

    def display_name
      name.presence || fingerprint
    end
  end
end
