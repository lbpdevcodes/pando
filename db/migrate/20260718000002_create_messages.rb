# frozen_string_literal: true

class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :direction, null: false
      t.text :body
      t.string :status, null: false, default: "pending"
      # Dedup is per-direction: an outgoing message and the peer's incoming copy
      # share a content id, and only replays of the *same* direction are duplicates.
      t.string :content_id
      t.index [:content_id, :direction], unique: true
      t.string :sender_fingerprint
      t.datetime :sent_at, null: false
      t.datetime :expires_at
      t.timestamps
    end
  end
end
