# frozen_string_literal: true

module Pando
  # AttachPicker is the framework Filepicker plus what a modal needs: escape
  # cancels. Slot-declared, it lives for the screen's lifetime, so it reopens
  # in the directory the user last browsed.
  class AttachPicker < Charming::Components::Filepicker
    def handle_key(event)
      return :cancelled if Charming.key_of(event) == :escape

      super
    end
  end
end
