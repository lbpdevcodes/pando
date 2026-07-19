# frozen_string_literal: true

module Pando
  # ConversationList renders the sidebar: one row per conversation with a cursor
  # (sidebar focus), an active-conversation marker, and room for unread badges.
  class ConversationList < Charming::Component
    def initialize(conversations:, cursor_index:, active_id:, focused:, theme:, request_count: 0)
      super(theme: theme)
      @conversations = conversations
      @cursor_index = cursor_index
      @active_id = active_id
      @focused = focused
      @request_count = request_count
    end

    def render
      return column(*badge_rows, empty_row) if conversations.empty?

      column(*badge_rows, *rows)
    end

    private

    attr_reader :conversations, :cursor_index, :active_id, :focused, :request_count

    def badge_rows
      return [] unless request_count.positive?

      [text("! #{request_count} request#{"s" if request_count != 1}", style: theme.title)]
    end

    def empty_row
      text("No conversations yet.", style: theme.muted)
    end

    def rows
      conversations.each_with_index.map { |conversation, index| row_for(conversation, index) }
    end

    def row_for(conversation, index)
      cursor = (focused && index == cursor_index) ? ">" : " "
      active = (conversation.id == active_id) ? "\u{25cf}" : " "
      text "#{cursor} #{active} #{conversation.display_title}#{trust_glyph(conversation)}#{unread_suffix(conversation)}",
        style: row_style(conversation, index)
    end

    def unread_suffix(conversation)
      count = conversation.unread_count
      count.positive? ? " (#{count})" : ""
    end

    def trust_glyph(conversation)
      case conversation.contacts.first&.trust_level
      when "verified" then " \u{2713}"
      when "key_changed" then " !"
      else ""
      end
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
