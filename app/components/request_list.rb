# frozen_string_literal: true

module Pando
  # RequestList is the contact-request inbox: a selectable list of pending
  # incoming requests. Enter or `a` accepts the highlighted request, `d`
  # declines, escape closes — surfaced to the controller as component results.
  class RequestList < Charming::Components::List
    def initialize(requests:, selected_index: 0, theme: nil)
      super(items: requests, selected_index: selected_index, height: 8, theme: theme,
            label: ->(request) { "#{request.display_name} · #{request.fingerprint}" })
    end

    def handle_key(event)
      case Charming.key_of(event)
      when :a then selected_item && [:selected, [:accept, selected_item]]
      when :d then selected_item && [:selected, [:decline, selected_item]]
      when :escape then :cancelled
      when :enter then selected_item && [:selected, [:accept, selected_item]]
      else super
      end
    end
  end
end
