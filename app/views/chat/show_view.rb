# frozen_string_literal: true

module Pando
  module Chat
    class ShowView < Charming::View
      def render
        column(header, *alert_banner, transcript_block, composer_block, hints, gap: 1)
      end

      private

      def header
        title = active ? active.display_title : "No conversations"
        row(text(title, style: theme.title), *member_count, text("  ·  #{status}", style: status_style))
      end

      def member_count
        return [] unless active&.room?

        [text("  ·  #{active.member_count} members", style: theme.muted)]
      end

      def alert_banner
        return [] unless alert

        [text(alert, style: theme.warn)]
      end

      def status_style
        (status == "online") ? theme.info : theme.muted
      end

      def transcript_block
        render_component transcript
      end

      def composer_block
        render_component composer
      end

      def hints
        text "enter send · shift+enter newline · pgup/pgdn scroll · tab sidebar · ctrl+p commands",
          style: theme.muted
      end
    end
  end
end
