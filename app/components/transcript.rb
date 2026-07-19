# frozen_string_literal: true

module Pando
  # Transcript renders a conversation's messages inside a follow-mode viewport:
  # pinned to the newest message until the user scrolls up, re-engaging when they
  # return to the bottom. The controller persists offset/at_bottom? across events.
  class Transcript < Charming::Component
    def initialize(messages:, width:, height:, offset:, follow:, theme:)
      super(theme: theme)
      @messages = messages
      @viewport = Charming::Components::Viewport.new(
        content: content_lines.join("\n"),
        width: width, height: height, offset: offset, follow: follow, wrap: true
      )
    end

    def render
      @viewport.render
    end

    def offset = @viewport.offset

    def at_bottom? = @viewport.at_bottom?

    private

    attr_reader :messages

    def content_lines
      return [empty_notice] if messages.empty?

      messages.map { |message| format_message(message) }
    end

    def empty_notice
      "No messages yet — say hello."
    end

    def format_message(message)
      stamp = message.sent_at.localtime.strftime("%H:%M")
      label = message.outgoing? ? "you" : sender_label(message)
      suffix = message.outgoing? ? " #{message.status_glyph}" : ""
      "#{stamp} #{label}: #{message.body}#{suffix}"
    end

    def sender_label(message)
      message.sender_fingerprint.to_s[0, 8].presence || "them"
    end
  end
end
