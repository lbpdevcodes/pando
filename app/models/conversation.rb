# frozen_string_literal: true

module Pando
  class Conversation < ApplicationRecord
    has_many :messages, dependent: :destroy

    attribute :title, :pando_encrypted

    validates :key, presence: true, uniqueness: true
    validates :kind, inclusion: {in: %w[dm room]}

    scope :recent_first, -> { order(last_activity_at: :desc, id: :desc) }

    def display_title
      title.presence || key
    end

    def touch_activity(at: Time.now.utc)
      update!(last_activity_at: at)
    end
  end
end
