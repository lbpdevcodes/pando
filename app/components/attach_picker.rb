# frozen_string_literal: true

module Pando
  # AttachPicker is the framework Filepicker plus what a modal needs: escape
  # cancels, and the browsed directory can be restored across events (the
  # controller rebuilds components per dispatch, which would otherwise reset
  # navigation to the root every keypress).
  class AttachPicker < Charming::Components::Filepicker
    def initialize(current_dir: nil, **options)
      super(**options)
      restore(current_dir)
    end

    def handle_key(event)
      return :cancelled if Charming.key_of(event) == :escape

      super
    end

    private

    def restore(dir)
      return unless dir&.start_with?(@root) && File.directory?(dir)

      @current_dir = dir
      rebuild_list
    end
  end
end
