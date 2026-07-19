# frozen_string_literal: true

module Pando
  # RelayList is the switch-relay picker: saved relays with the active one
  # marked. Enter activates the highlighted relay; escape closes.
  class RelayList < Charming::Components::List
    def initialize(relays:, selected_index: 0, theme: nil)
      super(items: relays, selected_index: selected_index, height: 8, theme: theme,
            label: ->(relay) { "#{relay.active ? "\u{25cf}" : " "} #{relay.display_name}" })
    end

    def handle_key(event)
      return :cancelled if Charming.key_of(event) == :escape

      super
    end
  end
end
