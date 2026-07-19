# frozen_string_literal: true

class CreateContactRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :contact_requests do |t|
      t.string :fingerprint, null: false
      t.string :direction, null: false
      t.text :name
      t.text :bundle
      t.text :greeting
      t.string :status, null: false, default: "pending"
      t.string :content_id
      t.timestamps
      t.index [:fingerprint, :direction], unique: true
      # Unique per direction, like messages: our outgoing copy and the peer's
      # incoming copy legitimately share a content id.
      t.index [:content_id, :direction], unique: true
    end
  end
end
