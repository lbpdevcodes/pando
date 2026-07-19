# frozen_string_literal: true

module Pando
  class Message < ApplicationRecord
    STATUSES = %w[pending sent delivered failed].freeze
    DIRECTIONS = %w[incoming outgoing].freeze

    belongs_to :conversation
    has_one :attachment, dependent: :destroy

    attribute :body, :pando_encrypted

    validates :direction, inclusion: {in: DIRECTIONS}
    validates :status, inclusion: {in: STATUSES}
    validates :sent_at, presence: true

    scope :chronological, -> { order(:sent_at, :id) }

    def outgoing? = direction == "outgoing"

    def status_glyph
      {"pending" => "…", "sent" => "✓", "delivered" => "✓✓", "failed" => "✗"}.fetch(status)
    end
  end
end
