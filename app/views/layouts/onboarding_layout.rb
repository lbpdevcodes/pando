# frozen_string_literal: true

module Pando
  module Layouts
    class OnboardingLayout < Charming::View
      def render
        screen_layout(background: theme.background) do
          pane(:content, grow: 1, border: :rounded, padding: [2, 4]) do
            yield_content
          end

          overlay command_palette_modal if command_palette_modal
        end
      end

      private

      def command_palette_modal
        palette = assigns.fetch(:palette, nil)
        return unless palette

        render_component Charming::Components::CommandPaletteModal.new(content: palette, theme: theme)
      end
    end
  end
end
