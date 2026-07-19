# frozen_string_literal: true

module Pando
  class Conversation < ApplicationRecord
    has_many :messages, dependent: :destroy
    has_many :room_participants, dependent: :destroy

    attribute :title, :pando_encrypted

    validates :key, presence: true, uniqueness: true
    validates :kind, inclusion: {in: %w[dm room]}

    scope :recent_first, -> { order(last_activity_at: :desc, id: :desc) }

    def display_title
      title.presence || key
    end

    # The contacts that are participants in this conversation. A DM key embeds
    # the two account fingerprints ("dm:<fp>:<fp>"); rooms carry explicit
    # membership rows. Our own fingerprint never has a Contact row, so "everyone
    # but me" falls out of the join — the send path fans out to exactly this.
    def contacts
      Contact.where(fingerprint: participant_fingerprints)
    end

    def room?
      kind == "room"
    end

    def member_count
      room_participants.count
    end

    def touch_activity(at: Time.now.utc)
      update!(last_activity_at: at)
    end

    private

    def participant_fingerprints
      return room_participants.pluck(:fingerprint) if room?

      key.split(":").drop(1)
    end
  end
end
