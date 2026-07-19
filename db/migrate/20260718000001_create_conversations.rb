# frozen_string_literal: true

class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.string :key, null: false, index: {unique: true}
      t.string :kind, null: false, default: "dm"
      t.text :title
      t.datetime :last_activity_at
      t.timestamps
    end
  end
end
