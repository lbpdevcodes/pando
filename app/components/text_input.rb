# frozen_string_literal: true

module Pando
  # TextInput adds the public reset charming 0.4.0 lacks: a slot-declared
  # component lives for the screen's lifetime, so a modal input must be
  # cleared on close instead of rebuilt. replace_value is private upstream;
  # an implicit-self call from a subclass is the documented seam until
  # charming ships a value= setter (see charming's TODO).
  class TextInput < Charming::Components::TextInput
    # Empties the field and homes the cursor.
    def clear!
      replace_value("")
    end
  end
end
