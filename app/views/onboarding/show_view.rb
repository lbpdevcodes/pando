# frozen_string_literal: true

module Pando
  module Onboarding
    class ShowView < Charming::View
      def render
        column(title_line, prompt_line, input_line, error_line, hint_line, gap: 1)
      end

      private

      def title_line
        text "Pando", style: theme.header_accent
      end

      def prompt_line
        message = creating ? "Choose a passphrase for your new profile:" : "Enter your passphrase:"
        text message, style: theme.title
      end

      def input_line
        render_component passphrase
      end

      def error_line
        return text("", style: theme.muted) unless error

        text error, style: theme.warn
      end

      def hint_line
        text "enter unlock · ctrl+c quit", style: theme.muted
      end
    end
  end
end
