# frozen_string_literal: true

class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :direction, null: false
      t.text :body
      t.string :status, null: false, default: "pending"
      t.string :content_id, index: {unique: true}
      t.string :sender_fingerprint
      t.datetime :sent_at, null: false
      t.datetime :expires_at
      t.timestamps
    end
  end
end
