# frozen_string_literal: true

class AddTtlToConversations < ActiveRecord::Migration[8.1]
  def change
    # Per-conversation self-destruct timer in seconds; 0 = messages keep.
    add_column :conversations, :ttl, :integer, null: false, default: 0
    # The sweeper's WHERE expires_at <= now runs every second.
    add_index :messages, :expires_at
  end
end
