# frozen_string_literal: true

module Pando
  class ChatState < ApplicationState
    attribute :active_conversation_id, :integer
    attribute :cursor_index, :integer, default: 0
    attribute :transcript_offset, :integer, default: 0
    attribute :follow, :boolean, default: true
  end
end
