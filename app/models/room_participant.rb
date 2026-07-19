# frozen_string_literal: true

module Pando
  # RoomParticipant is one member of a room conversation, keyed by account
  # fingerprint — including our own row, so a snapshot that drops us is
  # detectable. DMs never have rows here; their members live in the key.
  class RoomParticipant < ApplicationRecord
    belongs_to :conversation

    validates :fingerprint, presence: true, uniqueness: {scope: :conversation_id}
  end
end
