# frozen_string_literal: true

module Pando
  # Setting is the encrypted local key-value store for small app preferences
  # (discoverability, etc). Values are encrypted at rest, so reads and writes
  # require an unlocked Store.
  class Setting < ApplicationRecord
    attribute :value, :pando_encrypted

    validates :key, presence: true, uniqueness: true

    def self.get(key)
      find_by(key: key)&.value
    end

    def self.put(key, value)
      record = find_or_initialize_by(key: key)
      record.value = value
      record.save!
      value
    end
  end
end
