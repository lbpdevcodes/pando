# frozen_string_literal: true

module Pando
  module Onboarding
    class ShowView < Charming::View
      def render
        return column(title_line, *waiting_lines, gap: 1) if mode == "enroll_waiting"

        column(title_line, prompt_line, input_line, error_line, hint_line, gap: 1)
      end

      private

      def title_line
        text "Pando", style: theme.header_accent
      end

      def prompt_line
        text prompt_message, style: theme.title
      end

      def prompt_message
        return "Choose a passphrase for this device:" if mode == "enroll"

        creating ? "Choose a passphrase for your new profile:" : "Enter your passphrase:"
      end

      def waiting_lines
        [
          text("Enrolling this device…", style: theme.title),
          text("On an enrolled device, run ctrl+p → Enroll a device and enter:", style: theme.muted),
          text("Code         #{enroll_code}", style: theme.info),
          text("Safety code  #{safety_code}", style: theme.info),
          text("Approve only if the safety codes match on both screens.", style: theme.warn),
          text("waiting for approval… · ctrl+c cancel", style: theme.muted)
        ]
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
