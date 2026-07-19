# frozen_string_literal: true

class AddUnreadCountToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :unread_count, :integer, null: false, default: 0
  end
end
