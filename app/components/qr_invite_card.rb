# frozen_string_literal: true

module Pando
  # QrInviteCard shows the user's invite as a scannable Kitty-rendered QR, or
  # — on terminals without graphics — the raw code wrapped for copying. Any
  # key dismisses.
  class QrInviteCard < Charming::Component
    ROWS = 20
    COLS = 40

    def initialize(source:, code:, theme: nil)
      super(theme: theme)
      @source = source
      @code = code
    end

    def render
      return image_block if @source&.supports_graphics?

      fallback_block
    end

    def handle_key(_event)
      :cancelled
    end

    private

    def image_block
      Charming::Components::Image.new(source: @source, rows: ROWS, cols: COLS).render
    end

    def fallback_block
      column(
        text("This terminal lacks graphics — share this code as text:", style: theme.muted),
        *@code.scan(/.{1,40}/).map { |line| text(line, style: theme.info) }
      )
    end
  end
end
