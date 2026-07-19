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
    # Correctness independent of the sweeper: expired rows never render even
    # if the background purge hasn't caught up.
    scope :unexpired, -> { where(expires_at: nil).or(where(expires_at: Time.now.utc..)) }

    def self.sweep_expired(now: Time.now.utc)
      where(expires_at: ..now).delete_all
    end

    def outgoing? = direction == "outgoing"

    def status_glyph
      {"pending" => "…", "sent" => "✓", "delivered" => "✓✓", "failed" => "✗"}.fetch(status)
    end
  end
end
