# frozen_string_literal: true

module Pando
  # ConversationList renders the sidebar: one row per conversation with a cursor
  # (sidebar focus), an active-conversation marker, and room for unread badges.
  class ConversationList < Charming::Component
    def initialize(conversations:, cursor_index:, active_id:, focused:, theme:)
      super(theme: theme)
      @conversations = conversations
      @cursor_index = cursor_index
      @active_id = active_id
      @focused = focused
    end

    def render
      return text("No conversations yet.", style: theme.muted) if conversations.empty?

      column(*rows)
    end

    private

    attr_reader :conversations, :cursor_index, :active_id, :focused

    def rows
      conversations.each_with_index.map { |conversation, index| row_for(conversation, index) }
    end

    def row_for(conversation, index)
      cursor = (focused && index == cursor_index) ? ">" : " "
      active = (conversation.id == active_id) ? "\u{25cf}" : " "
      text "#{cursor} #{active} #{conversation.display_title}", style: row_style(conversation, index)
    end

    def row_style(conversation, index)
      if focused && index == cursor_index
        theme.selected
      elsif conversation.id == active_id
        theme.title
      else
        theme.muted
      end
    end
  end
end
