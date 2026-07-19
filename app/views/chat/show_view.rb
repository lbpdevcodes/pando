# frozen_string_literal: true

module Pando
  module Chat
    class ShowView < Charming::View
      def render
        column(header, transcript_block, composer_block, hints, gap: 1)
      end

      private

      def header
        title = active ? active.display_title : "No conversations"
        text title, style: theme.title
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
