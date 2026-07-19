# frozen_string_literal: true

module Pando
  # Transcript renders a conversation's messages inside a follow-mode viewport:
  # pinned to the newest message until the user scrolls up, re-engaging when they
  # return to the bottom. The controller persists offset/at_bottom? across events.
  class Transcript < Charming::Component
    # *image_blocks* maps message ids to pre-rendered Kitty placement lines
    # (built by the controller while the escape collector is active).
    def initialize(messages:, width:, height:, offset:, follow:, theme:, image_blocks: {})
      super(theme: theme)
      @messages = messages
      @image_blocks = image_blocks
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

    attr_reader :messages, :image_blocks

    def content_lines
      return [empty_notice] if messages.empty?

      messages.flat_map { |message| message_lines(message) }
    end

    def empty_notice
      "No messages yet — say hello."
    end

    def message_lines(message)
      return [format_message(message)] unless message.kind == "attachment"

      [attachment_line(message), *image_blocks[message.id]]
    end

    def format_message(message)
      "#{prefix(message)}#{message.body}#{status_suffix(message)}"
    end

    def attachment_line(message)
      attachment = message.attachment
      detail = attachment ? " (#{attachment.display_size}) #{attachment.progress_label}".rstrip : ""
      icon = attachment&.voice ? "\u{1f3a4}" : "\u{1f4ce}"
      "#{prefix(message)}#{icon} #{message.body}#{detail}#{status_suffix(message)}"
    end

    def prefix(message)
      stamp = message.sent_at.localtime.strftime("%H:%M")
      label = message.outgoing? ? "you" : sender_label(message)
      "#{stamp} #{label}: "
    end

    def status_suffix(message)
      message.outgoing? ? " #{message.status_glyph}" : ""
    end

    def sender_label(message)
      message.sender_fingerprint.to_s[0, 8].presence || "them"
    end
  end
end
