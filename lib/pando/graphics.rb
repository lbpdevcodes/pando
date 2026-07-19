# frozen_string_literal: true

require "chunky_png"

module Pando
  # Graphics owns the terminal-graphics seam: protocol detection (injectable
  # for specs — never trust the test host's env) and the per-session cache of
  # Kitty image sources with a hard cap, so a long image transcript can never
  # grow terminal memory without bound.
  module Graphics
    MAX_SOURCES = 6
    MAX_PIXEL_WIDTH = 512
    MAX_CELL_COLS = 40
    MAX_CELL_ROWS = 15

    class << self
      attr_writer :terminal

      def terminal
        @terminal ||= Charming::Image::Terminal.new
      end

      def supports?
        terminal.supports_graphics?
      end
    end

    # Cache maps attachment ids to built {source:, rows:, cols:} entries.
    # Entries beyond MAX_SOURCES (or dropped by #retain) register the source's
    # Kitty delete so the terminal frees the pixels; a re-fetch rebuilds and
    # retransmits. Lives in session — Source#transmitted? gates the one-time
    # transmit only if the object survives across renders.
    class Cache
      def initialize(terminal: nil)
        @terminal = terminal
        @entries = {}
      end

      # Returns the cached entry for the attachment, building it from the
      # decrypted PNG bytes (yielded lazily) on a miss. Returns nil for bytes
      # ChunkyPNG can't parse.
      def fetch(attachment_id, max_cols: MAX_CELL_COLS)
        if (entry = @entries.delete(attachment_id))
          return @entries[attachment_id] = entry
        end

        entry = build(yield, max_cols: max_cols)
        return nil unless entry

        @entries[attachment_id] = entry
        evict_excess
        entry
      end

      # Drops (and releases) every cached source not in *ids*.
      def retain(ids)
        (@entries.keys - ids).each { |id| release(id) }
      end

      def release_all
        @entries.keys.each { |id| release(id) }
      end

      private

      def release(id)
        entry = @entries.delete(id)
        Charming::Escape.register(entry[:source].release) if entry
      end

      def evict_excess
        release(@entries.keys.first) while @entries.length > MAX_SOURCES
      end

      def build(png_bytes, max_cols:)
        image = ChunkyPNG::Image.from_blob(png_bytes)
        image = downscale(image)
        cols = [max_cols, MAX_CELL_COLS].min
        rows = (cols * (image.height.to_f / image.width) / 2.0).ceil.clamp(1, MAX_CELL_ROWS)
        source = Charming::Image::Source.new(data: image.to_blob, terminal: terminal)
        {source: source, rows: rows, cols: cols}
      rescue ChunkyPNG::Exception
        nil
      end

      # Cap the pixels resident in the terminal, not just the cell footprint.
      def downscale(image)
        return image if image.width <= MAX_PIXEL_WIDTH

        image.resample_bilinear(MAX_PIXEL_WIDTH,
          [(image.height * MAX_PIXEL_WIDTH.to_f / image.width).round, 1].max)
      end

      def terminal
        @terminal || Graphics.terminal
      end
    end
  end
end
