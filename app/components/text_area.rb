# frozen_string_literal: true

module Pando
  # TextArea adds what the composer needs under charming 0.4.0's persistent
  # controllers: value= to swap per-conversation drafts in and out, clear!
  # after a send, and placeholder/width writers so the render can refresh
  # them (the same data-refresh idiom as List#items=). The writers touch
  # upstream internals directly — to be retired when charming ships the
  # setters (see charming's TODO).
  class TextArea < Charming::Components::TextArea
    # The parent keeps these readers private; the render-refresh idiom needs them public.
    attr_accessor :placeholder, :width

    # Replaces the whole draft and lands the cursor at its end.
    def value=(text)
      @value = text.dup
      @cursor = @value.length
      @offset = 0
      @preferred_column = nil
    end

    # Empties the draft after a send.
    def clear!
      self.value = ""
    end
  end
end
